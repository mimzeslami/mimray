package main

import (
	"net"

	"golang.org/x/sys/unix"
)

// peerUID returns the uid of the process on the other end of the socket.
func peerUID(c *net.UnixConn) (int, error) {
	raw, err := c.SyscallConn()
	if err != nil {
		return -1, err
	}
	uid := -1
	var gerr error
	err = raw.Control(func(fd uintptr) {
		var x *unix.Xucred
		x, gerr = unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
		if gerr == nil {
			uid = int(x.Uid)
		}
	})
	if err != nil {
		return -1, err
	}
	return uid, gerr
}
