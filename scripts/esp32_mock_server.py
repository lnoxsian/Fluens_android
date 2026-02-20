import argparse
import asyncio
import json
import logging
import time
import sys
from aiohttp import web

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variable for current message
current_message = None
current_message_id = None

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
        logger.info(f"App polled message: {current_message}")
    
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
    print("Type a message for the app and press Enter.")
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
                print(f"[Queued]: '{msg}' (waiting for app poll)")
                print("> ", end='', flush=True)
                
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Input error: {e}")

async def start_background_tasks(app):
    app['input_task'] = asyncio.create_task(console_input_loop())

async def cleanup_background_tasks(app):
    app['input_task'].cancel()
    try:
        await app['input_task']
    except asyncio.CancelledError:
        pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ESP32 Mock Server (Polling)")
    parser.add_argument("--port", type=int, default=8080, help="Port to listen on")
    parser.add_argument("--host", default="0.0.0.0", help="Host interface")
    args = parser.parse_args()

    app = web.Application()
    app.router.add_get('/messages', handle_get_messages)
    app.router.add_post('/response', handle_post_response)
    
    app.on_startup.append(start_background_tasks)
    app.on_cleanup.append(cleanup_background_tasks)

    print(f"Starting Poll Server at http://{args.host}:{args.port}")
    print("Endpoints:")
    print(f"  GET  /messages  - Returns current message")
    print(f"  POST /response  - Receives AI answer")
    
    web.run_app(app, host=args.host, port=args.port)
