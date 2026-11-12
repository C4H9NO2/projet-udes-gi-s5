import threading

# Le bus I2C est partage entre les roues et le capteur de
# ligne : on utilise donc un lock pour eviter des collisions sur le bus I2C.
hardware_lock = threading.Lock()