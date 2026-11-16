from typing import Literal


from picar import back_wheels, front_wheels

from hardware_lock import hardware_lock

_STRAIGHT_ANGLE = 90
_TURNING_MAX = 45

_back = back_wheels.Back_Wheels(db="config")
_front = front_wheels.Front_Wheels(db="config")
_front.turning_max = _TURNING_MAX

_back.ready()
_front.ready()

# Etat précédent des roues, pour ne pas reecrire l'I2C inutilement si ça n'a pas changé
_previous_direction_command = _STRAIGHT_ANGLE
_previous_signed_velocity_command = 0

def drive(velocity, direction):
    """
    Applique une commande de conduite (vitesse normalisee + braquage) aux roues
    """

    global _previous_direction_command, _previous_signed_velocity_command

    # Le bus I2C est utilisé à la fois par les roues et par le capteur de ligne, 
    # donc on doit utiliser un lock pour éviter des collisions sur le bus I2C.
    with hardware_lock:

        direction_command = int(round(_STRAIGHT_ANGLE - direction * _TURNING_MAX))
        signed_velocity_command = int(round(min(velocity, 1.0) * 100))

        if direction_command != _previous_direction_command:
            _front.turn(direction_command)
            _previous_direction_command = direction_command

        # On compare la commande signée : sinon un passage de la marche avant à la
        # marche arrière à même vitesse ne réappliquerait pas le sens aux roues.
        if signed_velocity_command != _previous_signed_velocity_command:
            if signed_velocity_command == 0:
                _back.stop()
            else:
                if signed_velocity_command > 0:
                    _back.forward()
                else:
                    _back.backward()
                _back.speed = abs(signed_velocity_command)

            _previous_signed_velocity_command = signed_velocity_command

def stop_car():
    """
    Arrete les roues (vitesse = 0)
    """
    drive(0, 0)