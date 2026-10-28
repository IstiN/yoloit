//go:build windows

package session

import (
	"context"
	"log"
	"os"
	"os/exec"
	"strconv"

	"github.com/UserExistsError/conpty"
)

// conSessionPty implements ptyMaster/ptyProcess on top of the Windows
// pseudoconsole API (ConPTY). os/exec cannot start a process attached to a
// pseudoconsole (golang/go#62708), so the child is created by the conpty
// package with the ProcThreadAttributeList dance.
type conSessionPty struct {
	c        *conpty.ConPty
	exitCode int
}

// startSessionPty spawns the command attached to a ConPTY console. The
// command string is passed verbatim as a CreateProcess command line — no
// sh -c wrapping and no arg splitting (Windows quoting rules apply).
func startSessionPty(command, cwd string, env []string, cols, rows int) (ptyMaster, ptyProcess, error) {
	c, err := conpty.Start(command,
		conpty.ConPtyDimensions(cols, rows),
		conpty.ConPtyWorkDir(cwd),
		conpty.ConPtyEnv(env),
	)
	if err != nil {
		return nil, nil, err
	}
	p := &conSessionPty{c: c}
	return p, p, nil
}

// defaultShellCommand resolves the interactive shell when the create request
// does not name one. The YoLoIT client normally sends an explicit command;
// COMSPEC (cmd.exe) is the idiomatic Windows fallback.
func defaultShellCommand() string {
	if sh := os.Getenv("COMSPEC"); sh != "" {
		return sh
	}
	return "cmd.exe"
}

func (p *conSessionPty) Read(b []byte) (int, error)        { return p.c.Read(b) }
func (p *conSessionPty) WriteString(s string) (int, error) { return p.c.Write([]byte(s)) }
func (p *conSessionPty) Close() error                      { return p.c.Close() }

func (p *conSessionPty) resize(cols, rows int) error {
	return p.c.Resize(cols, rows)
}

// sameSizeRedrawNudge is a legitimate no-op on Windows: there is no
// SIGWINCH. GenerateConsoleCtrlEvent delivers Ctrl-C/Break semantics, not
// "repaint yourself" — and ConPTY repaints attached TUIs itself in response
// to ResizePseudoConsole, so the client's attach-time same-size re-sync is
// already covered.
func (p *conSessionPty) sameSizeRedrawNudge(fallbackPID int) error {
	log.Printf("[session] redraw no-op: ConPTY repaints on resize (pid=%d)", p.PID())
	return nil
}

// Wait blocks until the child exits and remembers its exit code. conpty
// polls the process handle; after Wait returns, the session's waitLoop
// closes the pseudoconsole so readLoop drains and unblocks.
func (p *conSessionPty) Wait() error {
	code, err := p.c.Wait(context.Background())
	p.exitCode = int(code)
	return err
}

func (p *conSessionPty) PID() int      { return p.c.Pid() }
func (p *conSessionPty) ExitCode() int { return p.exitCode }

// Kill force-terminates the whole process tree (shell + spawned CLI tools).
// ConPTY has no POSIX signals; closing the pseudoconsole (done in waitLoop
// after exit) additionally destroys the console the children are attached to.
func (p *conSessionPty) Kill() {
	pid := p.PID()
	if pid == 0 {
		return
	}
	_ = exec.Command("taskkill", "/PID", strconv.Itoa(pid), "/T", "/F").Run()
}
