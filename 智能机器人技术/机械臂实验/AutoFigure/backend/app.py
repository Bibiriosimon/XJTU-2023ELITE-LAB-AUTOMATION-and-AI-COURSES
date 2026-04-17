"""
AutoFigure Backend - Standalone Flask Application
Minimal Flask server for AutoFigure API endpoints.
"""

import os
import sys
from pathlib import Path

# Add paths for imports
try:
    backend_path = Path(__file__).parent
except NameError:
    backend_path = Path.cwd()
autofigure_path = backend_path.parent / 'autofigure'
sys.path.insert(0, str(backend_path))
sys.path.insert(0, str(autofigure_path))

from flask import Flask
from flask_cors import CORS

# Create Flask app
app = Flask(__name__)

# Enable CORS for frontend - LOCAL ACCESS ONLY
CORS(app, resources={
    r"/api/*": {
        "origins": ["http://localhost:3000", "http://localhost:6002", "http://localhost:6001", "http://127.0.0.1:3000", "http://127.0.0.1:6002", "http://127.0.0.1:6001"],
        "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        "allow_headers": ["Content-Type", "Authorization"]
    }
})

# Health check endpoint
@app.route('/health', methods=['GET'])
def health_check():
    return {'status': 'healthy', 'service': 'autofigure-backend'}

@app.route('/api/health', methods=['GET'])
def api_health_check():
    return {'status': 'healthy', 'service': 'autofigure-backend', 'autofigure': True}

# Register AutoFigure routes
try:
    from autofigure_routes import register_autofigure_routes
    register_autofigure_routes(app)
    print("[AutoFigure] Routes registered successfully")
except ImportError as e:
    print(f"[AutoFigure] Warning: Could not import autofigure_routes: {e}")

if __name__ == '__main__':
    port = int(os.environ.get('AUTOFIGURE_BACKEND_PORT', 8796))
    host = os.environ.get('AUTOFIGURE_HOST', '127.0.0.1')
    print(f"[AutoFigure] Starting backend server on http://{host}:{port}")
    if host in ('127.0.0.1', 'localhost'):
        print(f"[AutoFigure] LOCAL ACCESS ONLY - Public network access is disabled")
    print(f"[AutoFigure] Backend path: {backend_path}")
    print(f"[AutoFigure] AutoFigure path: {autofigure_path}")
    # NOTE: use_reloader=False is required to prevent Flask from restarting when
    # Playwright or other libraries modify files during execution (especially on Windows)
    app.run(host=host, port=port, debug=True, use_reloader=False)
