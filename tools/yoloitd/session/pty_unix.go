//go:build !windows

package session

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/creack/pty"
)

// unixSessionPty implements ptyMaster/ptyProcess with os/exec + creack/pty —
// byte-for-byte the pre-Windows behavior (SIGWINCH redraw nudge included).
type unixSessionPty struct {
	ptmx *os.File
	cmd  *exec.Cmd
}

// startSessionPty spawns the command attached to a unix PTY.
func startSessionPty(command, cwd string, env []string, cols, rows int) (ptyMaster, ptyProcess, error) {
	var cmd *exec.Cmd
	if strings.Contains(command, " ") {
		cmd = exec.Command("sh", "-c", command)
	} else {
		// Plain interactive shell — login shells (-l) can re-source profile files
		// and drop env vars injected by YoLoIT env groups.
		cmd = exec.Command(command)
	}
	cmd.Dir = cwd
	cmd.Env = env

	ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{
		Cols: uint16(cols),
		Rows: uint16(rows),
	})
	if err != nil {
		return nil, nil, err
	}
	p := &unixSessionPty{ptmx: ptmx, cmd: cmd}
	return p, p, nil
}

// defaultShellCommand resolves the interactive shell when the create request
// does not name one.
func defaultShellCommand() string {
	if sh := os.Getenv("SHELL"); sh != "" {
		return sh
	}
	return "/bin/sh"
}

func (p *unixSessionPty) Read(b []byte) (int, error)        { return p.ptmx.Read(b) }
func (p *unixSessionPty) WriteString(s string) (int, error) { return p.ptmx.WriteString(s) }
func (p *unixSessionPty) Close() error                      { return p.ptmx.Close() }

func (p *unixSessionPty) resize(cols, rows int) error {
	return pty.Setsize(p.ptmx, &pty.Winsize{
		Cols: uint16(cols),
		Rows: uint16(rows),
	})
}

// sameSizeRedrawNudge sends SIGWINCH to the PTY's foreground process group so
// an alt-buffer TUI repaints even though the dimensions did not change.
func (p *unixSessionPty) sameSizeRedrawNudge(fallbackPID int) error {
	pgrp, err := foregroundProcessGroup(p.ptmx.Fd())
	if err != nil {
		// Non-job-control shells normally own the foreground group. Keep the
		// redraw best-effort on platforms without a known TIOCGPGRP value.
		pgrp = fallbackPID
	}
	log.Printf("[session] redraw reason=same-size-alt-resize pgrp=%d", pgrp)
	return syscall.Kill(-pgrp, syscall.SIGWINCH)
}

func (p *unixSessionPty) Wait() error { return p.cmd.Wait() }

func (p *unixSessionPty) PID() int {
	if p.cmd.Process != nil {
		return p.cmd.Process.Pid
	}
	return 0
}

func (p *unixSessionPty) ExitCode() int {
	if p.cmd.ProcessState != nil {
		return p.cmd.ProcessState.ExitCode()
	}
	return 0
}

// Kill terminates gracefully: SIGTERM first, then a delayed SIGKILL if the
// process ignores the term signal.
func (p *unixSessionPty) Kill() {
	if p.cmd.Process == nil {
		return
	}
	_ = p.cmd.Process.Signal(syscall.SIGTERM)
	pid := p.cmd.Process.Pid
	go func() {
		time.Sleep(2 * time.Second)
		_ = syscall.Kill(pid, syscall.SIGKILL)
	}()
}

// foregroundProcessGroup returns the PTY's foreground job, which is normally
// the TUI process group rather than the interactive shell's process group.
func foregroundProcessGroup(fd uintptr) (int, error) {
	// TIOCGPGRP is not exported by the frozen syscall package on Darwin.
	const bsdTiocgpgrp = 0x40047477 // _IOR('t', 119, int)
	const linuxTiocgpgrp = 0x540f
	var request uintptr
	switch runtime.GOOS {
	case "darwin", "freebsd", "netbsd", "openbsd", "dragonfly":
		request = bsdTiocgpgrp
	case "linux":
		request = linuxTiocgpgrp
	default:
		return 0, fmt.Errorf("TIOCGPGRP is unsupported on %s", runtime.GOOS)
	}
	var pgrp int32
	_, _, errno := syscall.Syscall(
		syscall.SYS_IOCTL,
		fd,
		request,
		uintptr(unsafe.Pointer(&pgrp)),
	)
	if errno != 0 {
		return 0, errno
	}
	if pgrp <= 0 {
		return 0, fmt.Errorf("invalid foreground process group %d", pgrp)
	}
	return int(pgrp), nil
}
