import crypto from 'node:crypto'
import net from 'node:net'
import tls from 'node:tls'
import { URL } from 'node:url'

class SocketReader {
  private chunks: Buffer[] = []
  private length = 0
  private waiters: Array<() => void> = []

  constructor(private readonly socket: net.Socket | tls.TLSSocket, initial?: Buffer) {
    if (initial?.length) this.push(initial)
    this.socket.on('data', (chunk: Buffer) => this.push(chunk))
  }

  private push(chunk: Buffer): void {
    this.chunks.push(chunk)
    this.length += chunk.length
    for (const waiter of this.waiters.splice(0)) waiter()
  }

  private async waitForData(timeoutMs: number): Promise<void> {
    if (this.length > 0) return
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiters = this.waiters.filter((waiter) => waiter !== done)
        reject(new Error(`Timed out waiting for websocket data after ${timeoutMs}ms`))
      }, timeoutMs)
      const done = () => {
        clearTimeout(timer)
        resolve()
      }
      this.waiters.push(done)
    })
  }

  async read(length: number, timeoutMs = 8_000): Promise<Buffer> {
    const parts: Buffer[] = []
    let remaining = length

    while (remaining > 0) {
      await this.waitForData(timeoutMs)
      const chunk = this.chunks.shift()
      if (!chunk) continue
      this.length -= chunk.length

      if (chunk.length <= remaining) {
        parts.push(chunk)
        remaining -= chunk.length
      } else {
        parts.push(chunk.subarray(0, remaining))
        const rest = chunk.subarray(remaining)
        this.chunks.unshift(rest)
        this.length += rest.length
        remaining = 0
      }
    }

    return Buffer.concat(parts)
  }
}

async function readHttpHeader(socket: net.Socket | tls.TLSSocket): Promise<{ header: string; leftover: Buffer }> {
  const chunks: Buffer[] = []

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timed out waiting for websocket handshake')), 10_000)

    const onData = (chunk: Buffer) => {
      chunks.push(chunk)
      const combined = Buffer.concat(chunks)
      const idx = combined.indexOf('\r\n\r\n')
      if (idx === -1) return

      clearTimeout(timer)
      socket.off('data', onData)
      resolve({
        header: combined.subarray(0, idx + 4).toString('utf8'),
        leftover: combined.subarray(idx + 4),
      })
    }

    socket.on('data', onData)
    socket.once('error', reject)
  })
}

function sendTextFrame(socket: net.Socket | tls.TLSSocket, text: string): void {
  const data = Buffer.from(text)
  const header: number[] = [0x81]

  if (data.length < 126) {
    header.push(0x80 | data.length)
  } else if (data.length < 65_536) {
    header.push(0x80 | 126, (data.length >> 8) & 0xff, data.length & 0xff)
  } else {
    throw new Error('WebSocket test frame is too large')
  }

  const mask = crypto.randomBytes(4)
  const masked = Buffer.alloc(data.length)
  for (let i = 0; i < data.length; i += 1) {
    masked[i] = data[i] ^ mask[i % 4]
  }

  socket.write(Buffer.concat([Buffer.from(header), mask, masked]))
}

async function readTextFrame(reader: SocketReader): Promise<string> {
  const head = await reader.read(2)
  const opcode = head[0] & 0x0f
  let length = head[1] & 0x7f

  if (length === 126) {
    length = (await reader.read(2)).readUInt16BE(0)
  } else if (length === 127) {
    const big = (await reader.read(8)).readBigUInt64BE(0)
    if (big > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('WebSocket frame is too large')
    length = Number(big)
  }

  const payload = await reader.read(length)
  if (opcode !== 1) return `<opcode ${opcode} ${length} bytes>`
  return payload.toString('utf8')
}

export async function realtimeJoin(baseUrl: string, anonKey: string): Promise<{ statusLine: string; message: string }> {
  const parsed = new URL(baseUrl)
  const port = Number(parsed.port || (parsed.protocol === 'https:' ? 443 : 80))
  const host = parsed.hostname
  const socket =
    parsed.protocol === 'https:'
      ? tls.connect({ host, port, servername: host, rejectUnauthorized: false })
      : net.connect({ host, port })

  await new Promise<void>((resolve, reject) => {
    if (parsed.protocol === 'https:') {
      socket.once('secureConnect', resolve)
    } else {
      socket.once('connect', resolve)
    }
    socket.once('error', reject)
  })

  const wsKey = crypto.randomBytes(16).toString('base64')
  const hostHeader = parsed.port ? `${host}:${port}` : host
  socket.write(
    [
      `GET /realtime/v1/websocket?apikey=${encodeURIComponent(anonKey)}&vsn=1.0.0 HTTP/1.1`,
      `Host: ${hostHeader}`,
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Key: ${wsKey}`,
      'Sec-WebSocket-Version: 13',
      `Origin: ${baseUrl}`,
      '',
      '',
    ].join('\r\n'),
  )

  const { header, leftover } = await readHttpHeader(socket)
  const statusLine = header.split('\r\n')[0]
  if (!statusLine.includes('101')) {
    socket.destroy()
    throw new Error(`WebSocket upgrade failed: ${statusLine}`)
  }

  const reader = new SocketReader(socket, leftover)
  const join = {
    topic: 'realtime:public:codex_probe',
    event: 'phx_join',
    payload: {
      config: {
        broadcast: { self: false },
        presence: { key: '' },
        postgres_changes: [],
      },
      access_token: anonKey,
    },
    ref: '1',
  }

  sendTextFrame(socket, JSON.stringify(join))
  const message = await readTextFrame(reader)
  socket.destroy()
  return { statusLine, message }
}
