import argparse
import asyncio
import json
import logging
import time
import sys
import socket
from aiohttp import web

logging.basicConfig(level=logging.WARNING) # Reduce log level
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO) # Keep our logs visible

# Global variable for current message
current_message = None
current_message_id = None

async def udp_discovery_loop(http_port):
    """
    Listens for UDP broadcast discovery packets and responds logic.
    """
    UDP_PORT = 12345
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # Allow multiple sockets to use the same PORT number
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(('0.0.0.0', UDP_PORT))
        sock.setblocking(False)
        logger.info(f"UDP Discovery Server listening on port {UDP_PORT}")
    except Exception as e:
        logger.error(f"Failed to bind UDP port {UDP_PORT}: {e}")
        return

    loop = asyncio.get_event_loop()

    while True:
        try:
            data, addr = await loop.sock_recvfrom(sock, 1024)
            message = data.decode('utf-8').strip()
            
            if message == "FLUENS_DISCOVER":
                # Respond with our HTTP port
                response = f"FLUENS_ESP32_HERE:{http_port}"
                sock.sendto(response.encode('utf-8'), addr)
                logger.info(f"Received discovery from {addr}, responded with {response}")
                
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"UDP Error: {e}")
            await asyncio.sleep(1)
    
    sock.close()

async def handle_get_messages(request):
    """
    Handle poll request from app.
    Returns:
       {"message": "The message", "id": "unique-id"} if a message exists.
       {} empty JSON if no message.
    """
    global current_message
    
    data = {}
    if current_message:
        data = {
            "message": current_message,
            "id": current_message_id
        }
        # Only log once per message ID to avoid spam
        # logger.info(f"App polled message: {current_message}")
    
    return web.Response(text=json.dumps(data), content_type='application/json')

async def handle_post_response(request):
    """
    Handle AI response from app.
    Expects: {"response": "The AI response text"}
    """
    try:
        data = await request.json()
        response_text = data.get('response', '')
        print(f"\n[APP SAYS]: {response_text}\n> ", end='', flush=True)
        return web.Response(text="OK")
    except Exception as e:
        logger.error(f"Error handling response: {e}")
        return web.Response(status=400)

async def console_input_loop():
    """Simple blocking input loop running in executor"""
    global current_message, current_message_id
    print("\n---------------------------------------------------")
    print(" ESP32 MOCK SERVER")
    print("---------------------------------------------------")
    print(" App will automatically discover this server.")
    print(" Type a message below and press ENTER to send to the app.")
    print("---------------------------------------------------")
    print("> ", end='', flush=True)
    
    loop = asyncio.get_event_loop()
    while True:
        try:
            # Run blocking input in a separate thread so it doesn't block the server
            msg = await loop.run_in_executor(None, sys.stdin.readline)
            if not msg:
                break
                
            msg = msg.strip()
            if msg:
                current_message = msg
                current_message_id = str(int(time.time() * 1000))
                # print(f"[Queued]: '{msg}'")
                print("> ", end='', flush=True)
                
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Input error: {e}")

async def start_background_tasks(app):
    app['input_task'] = asyncio.create_task(console_input_loop())
    app['udp_task'] = asyncio.create_task(udp_discovery_loop(app['http_port']))

async def cleanup_background_tasks(app):
    app['input_task'].cancel()
    app['udp_task'].cancel()
    try:
        await app['input_task']
        await app['udp_task']
    except asyncio.CancelledError:
        pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ESP32 Mock Server (Polling)")
    parser.add_argument("--port", type=int, default=8080, help="Port to listen on")
    parser.add_argument("--host", default="0.0.0.0", help="Host interface")
    args = parser.parse_args()

    app = web.Application()
    app['http_port'] = args.port
    app.router.add_get('/messages', handle_get_messages)
    app.router.add_post('/response', handle_post_response)
    
    app.on_startup.append(start_background_tasks)
    app.on_cleanup.append(cleanup_background_tasks)

    print(f"Starting Poll Server at http://{args.host}:{args.port}")
    # Disable access logs to keep console clean for chat
    web.run_app(app, host=args.host, port=args.port, access_log=None, print=None)
