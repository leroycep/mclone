const std = @import("std");
const Address = std.net.Address;
const fs = std.fs;
const os = std.os;
const mem = std.mem;

pub const NonblockingStreamServer = struct {
    /// Copied from `Options` on `init`.
    kernel_backlog: u31,
    reuse_address: bool,

    /// `undefined` until `listen` returns successfully.
    listen_address: Address,

    sockfd: ?os.socket_t,

    pub const Options = struct {
        /// How many connections the kernel will accept on the application's behalf.
        /// If more than this many connections pool in the kernel, clients will start
        /// seeing "Connection refused".
        kernel_backlog: u31 = 128,

        /// Enable SO_REUSEADDR on the socket.
        reuse_address: bool = false,
    };

    /// After this call succeeds, resources have been acquired and must
    /// be released with `deinit`.
    pub fn init(options: Options) NonblockingStreamServer {
        return NonblockingStreamServer{
            .sockfd = null,
            .kernel_backlog = options.kernel_backlog,
            .reuse_address = options.reuse_address,
            .listen_address = undefined,
        };
    }

    /// Release all resources. The `NonblockingStreamServer` memory becomes `undefined`.
    pub fn deinit(self: *NonblockingStreamServer) void {
        self.close();
        self.* = undefined;
    }

    pub fn listen(self: *NonblockingStreamServer, address: Address) !void {
        const sock_flags = os.SOCK_STREAM | os.SOCK_CLOEXEC | os.SOCK_NONBLOCK;
        const proto = if (address.any.family == os.AF_UNIX) @as(u32, 0) else os.IPPROTO_TCP;

        const sockfd = try os.socket(address.any.family, sock_flags, proto);
        self.sockfd = sockfd;
        errdefer {
            os.closeSocket(sockfd);
            self.sockfd = null;
        }

        if (self.reuse_address) {
            try os.setsockopt(
                sockfd,
                os.SOL_SOCKET,
                os.SO_REUSEADDR,
                &mem.toBytes(@as(c_int, 1)),
            );
        }

        var socklen = address.getOsSockLen();
        try os.bind(sockfd, &address.any, socklen);
        try os.listen(sockfd, self.kernel_backlog);
        try os.getsockname(sockfd, &self.listen_address.any, &socklen);
    }

    /// Stop listening. It is still necessary to call `deinit` after stopping listening.
    /// Calling `deinit` will automatically call `close`. It is safe to call `close` when
    /// not listening.
    pub fn close(self: *NonblockingStreamServer) void {
        if (self.sockfd) |fd| {
            os.closeSocket(fd);
            self.sockfd = null;
            self.listen_address = undefined;
        }
    }

    pub const AcceptError = error{
        ConnectionAborted,

        /// The per-process limit on the number of open file descriptors has been reached.
        ProcessFdQuotaExceeded,

        /// The system-wide limit on the total number of open files has been reached.
        SystemFdQuotaExceeded,

        /// Not enough free memory.  This often means that the memory allocation  is  limited
        /// by the socket buffer limits, not by the system memory.
        SystemResources,

        /// Socket is not listening for new connections.
        SocketNotListening,

        ProtocolFailure,

        /// Firewall rules forbid connection.
        BlockedByFirewall,

        /// Permission to create a socket of the specified type and/or
        /// protocol is denied.
        PermissionDenied,

        FileDescriptorNotASocket,

        ConnectionResetByPeer,

        NetworkSubsystemFailed,

        OperationNotSupported,

        WouldBlock,
    } || os.UnexpectedError;

    pub const Connection = struct {
        file: fs.File,
        address: Address,
    };

    /// If this function succeeds, the returned `Connection` is a caller-managed resource.
    pub fn accept(self: *NonblockingStreamServer) AcceptError!Connection {
        var accepted_addr: Address = undefined;
        var adr_len: os.socklen_t = @sizeOf(Address);
        const fd = try os.accept(self.sockfd.?, &accepted_addr.any, &adr_len, os.SOCK_CLOEXEC | os.SOCK_NONBLOCK);

        return Connection{
            .file = fs.File{ .handle = fd },
            .address = accepted_addr,
        };
    }
};
