import time, collections, collections.abc
from prometheus_client import start_http_server, Gauge, Info

if not hasattr(collections, 'Mapping'):
    collections.Mapping = collections.abc.Mapping
import valve.source.a2s

SERVER_ADDRESS = ("127.0.0.1", 27015)
EXPORTER_PORT = 9137

cs2_up = Gauge('cs2_server_up', 'Server Status')
cs2_players = Gauge('cs2_player_count', 'Player Count')
cs2_map = Info('cs2_current_map', 'Map Information')

def fetch_metrics():
    try:
        with valve.source.a2s.ServerQuerier(SERVER_ADDRESS, timeout=5) as server:
            info = server.info()
            cs2_up.set(1)
            cs2_players.set(info["player_count"])
            map_name = info.get("map_name", info.get("map", "Unknown"))
            cs2_map.info({'map_name': map_name})
    except Exception:
        # If connection fails, set players to 0 and map to Offline
        cs2_up.set(0)
        cs2_players.set(0)
        cs2_map.info({'map_name': 'Offline'})

if __name__ == '__main__':
    start_http_server(EXPORTER_PORT)
    while True:
        fetch_metrics()
        time.sleep(15)