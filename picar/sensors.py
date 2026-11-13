import asyncio
import logging
import json

from SunFounder_Line_Follower import Line_Follower
from Ultrasonic_Avoidance import Ultrasonic_Avoidance
from hardware_lock import hardware_lock

_LINE_REFERENCES = [50, 50, 50, 50, 50]  # a recalibrer selon la surface
_SENSOR_PERIOD_S = 0.05 # temps entre deux lectures de capteurs, en secondes

_ULTRASON_TRIG = 12  # B12 (bleu)
_ULTRASON_ECHO = 16  # B16 (jaune)

_line_follower = Line_Follower.Line_Follower(references=_LINE_REFERENCES)
_ultrasonic = Ultrasonic_Avoidance(_ULTRASON_TRIG, _ULTRASON_ECHO)
_logger = logging.getLogger("picar")

# Derniere lecture des capteurs, lue par le main
_current_sensors_values = {"distance": -1, "line_follower": [0, 0, 0, 0, 0]}

def _read_distance():
    """
    Lit et renvoie la distance en cm lue par le capteur a ultrasons (-1 si echec).
    """
    try:
        distance = _ultrasonic.distance()
    except Exception:  # noqa: BLE001 - capteur debranche, GPIO indisponible...
        _logger.warning("Lecture du capteur a ultrasons impossible")
        return -1

    if distance is None or distance < 0:
        _logger.debug("Distance invalide lue par le capteur a ultrasons : %r", distance)
        return -1

    distance = int(round(distance))
    _logger.debug("Distance mesuree : %d cm", distance)
    return distance

def _read_lines():
    """
    Lit et renvoie la liste des valeurs lues par les capteurs de ligne.
    """
    raw_values = _line_follower.read_digital()
    values = [1 if value == 1 else 0 for value in raw_values]
    # -1 signifie que la lecture est ambigue (valeur analogique egale a la reference)
    _logger.debug("Capteurs de ligne : brut=%s normalise=%s", [float(value) for value in raw_values], values)
    return values


def _read_sensors_values():
    """
    Lit tous les capteurs et renvoie un instantané de leur etat.
    """
    distance = _read_distance()

    try:
        # Les capteurs de ligne utilisent le bus I2C et les roues aussi.
        # Il faut donc un lock pour éviter des collisions sur le bus I2C
        with hardware_lock:
            line_follower_values = _read_lines()
    except Exception:  # noqa: BLE001 - capteur debranche, bus I2C occupe...
        _logger.warning("Lecture du capteur de ligne impossible")
        line_follower_values = _current_sensors_values["line_follower"]

    return {"distance": distance, "line_follower": list(line_follower_values)}


async def start_reading_sensors(): 
    """
    Echantillonne les capteurs en continu, dans un thread à part.
    Stocke les valeurs lues dans `sensors_state`
    """
    while True:
        try:
            snapshot = await asyncio.to_thread(_read_sensors_values)
            _current_sensors_values.update(snapshot)
        except Exception:
            _logger.exception("Erreur pendant la lecture des capteurs")
        await asyncio.sleep(_SENSOR_PERIOD_S)

def get_serialized_sensors_values():
    """
    Serialise l'etat des capteurs au format attendu par Godot.
    """
    snapshot = _current_sensors_values
    return json.dumps(
        {
            "distance": int(snapshot["distance"]),
            "line_follower": [int(value) for value in snapshot["line_follower"]],
        }
    )
