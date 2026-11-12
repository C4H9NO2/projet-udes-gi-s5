#!/usr/bin/env python3
"""
Protocole de communication :
    Godot -> Python (~20 Hz) : {"velocity": 0.0-0.2, "direction": -1.0-1.0}
    PiCar -> Godot          : {"distance": <cm>, "line_follower": [0|1, 0|1, 0|1, 0|1, 0|1]}

`velocity` est une consigne de vitesse normalisee (0.2 correspond a 20 % de PWM,
voir `vitesse_m_s_par_unite_pwm` dans `config.json`), `direction` va de -1
(droite) a 1 (gauche).
"""

import asyncio
import json
import logging

from websockets.exceptions import ConnectionClosed
from websockets.server import serve

import picar
from sensors import start_reading_sensors, get_serialized_sensors_values
from wheels import drive, stop_car

PORT = 8765

logger = logging.getLogger("picar")
picar.setup()

def decode_json_from_godot(message):
    """
    Decode le message JSON de Godot et renvoie la vitesse et le braquage 
    """
    try:
        data = json.loads(message)
    except ValueError:
        logger.warning("Message ignore : JSON invalide %r", message)
        return None, None

    velocity = max(-1.0, min(1.0, float(data.get("velocity"))))
    direction = max(-1.0, min(1.0, float(data.get("direction"))))
    return velocity, direction

async def start_handling_websocket_client(websocket):
    """
    Fonction appelée à chaque connexion d'un client WebSocket (donc, normalement, une seule fois, quand Godot se connecte)
    Elle lit les commandes de conduite et renvoie les valeurs des capteurs en boucle jusqu'à ce que le client se déconnecte.
    """
    peer = websocket.remote_address
    logger.info("Connexion de %s", peer)

    try:
        while True:
            # On attend le prochain message de Godot
            message = await websocket.recv()

            # On lit les commandes de conduite que Godot nous a envoyées
            (velocity, direction) = decode_json_from_godot(message)
            if velocity is not None and direction is not None:
                # et on les applique
                drive(velocity, direction)

            # On renvoie l'état des capteurs à Godot
            await websocket.send(get_serialized_sensors_values())

    except ConnectionClosed:
        pass
    finally:
        stop_car()
        logger.info("Deconnexion de %s", peer)


async def main():
    # on lance la lecture des données des capteurs dans un thread à part
    sensor_task = asyncio.create_task(start_reading_sensors())

    try:
        # on lance le serveur WebSocket
        async with serve(start_handling_websocket_client, None, PORT):
            logger.info("Serveur WebSocket en ecoute sur le port %d", PORT)
            await asyncio.Future()  # tourne jusqu'a l'arret
    finally:
        sensor_task.cancel()
        stop_car()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Arret du serveur")
