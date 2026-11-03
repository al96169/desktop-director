// Minimal CONNECT proxy that pins github.com:443 to a reachable IP.
// Usage: node gh-proxy.js [port] [targetIp]
const net = require('net');
const port = Number(process.argv[2] || 8899);
const targetIp = process.argv[3] || '140.82.114.3';

const server = net.createServer((sock) => {
  sock.on('error', () => {});
  sock.once('data', (buf) => {
    const head = buf.toString('latin1');
    if (!/^CONNECT /i.test(head)) { sock.destroy(); return; }
    sock.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    const idx = buf.indexOf('\r\n\r\n');
    const rest = idx >= 0 ? buf.slice(idx + 4) : Buffer.alloc(0);
    const up = net.connect(443, targetIp, () => {
      if (rest.length) up.write(rest);
      sock.pipe(up);
      up.pipe(sock);
    });
    up.on('error', () => sock.destroy());
    sock.on('close', () => up.destroy());
  });
});
server.listen(port, '127.0.0.1', () => console.log(`gh-proxy listening on 127.0.0.1:${port} -> ${targetIp}:443`));
