import os, pty, sys, time, select, signal


def pump(fd, secs, out):
    end = time.time() + secs
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                d = os.read(fd, 65536)
            except OSError:
                return False
            if not d:
                return False
            out.write(d)
            out.flush()
    return True


pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
out = open(sys.argv[1], "wb")
pump(fd, 20, out)
for ch in "say hello":
    os.write(fd, ch.encode())
    time.sleep(0.05)
time.sleep(0.5)
os.write(fd, b"\r")
pump(fd, 20 + float(os.environ.get("IDLE", "0")), out)
os.write(fd, b"\x03")
pump(fd, 1, out)
os.write(fd, b"\x03")
pump(fd, 5, out)
try:
    os.kill(pid, signal.SIGTERM)
except ProcessLookupError:
    pass
os.waitpid(pid, 0)
