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
		var u *unix.Ucred
		u, gerr = unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
		if gerr == nil {
			uid = int(u.Uid)
		}
	})
	if err != nil {
		return -1, err
	}
	return uid, gerr
}
