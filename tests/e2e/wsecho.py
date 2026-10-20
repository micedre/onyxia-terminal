# /// script
# dependencies = ["websockets>=12"]
# ///
import asyncio
from websockets.asyncio.server import serve

async def echo(ws):
    async for m in ws:
        await ws.send(m)

async def main():
    async with serve(echo, "127.0.0.1", 8765):
        await asyncio.Future()

asyncio.run(main())
