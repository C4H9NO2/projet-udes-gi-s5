#!/usr/bin/env python3
import time

import RPi.GPIO as GPIO


class Ultrasonic_Avoidance(object):
    timeout = 0.03

    def __init__(self, trigger=16, echo=12):
        self.trigger = trigger
        self.echo = echo
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        GPIO.setup(self.trigger, GPIO.OUT)
        GPIO.setup(self.echo, GPIO.IN)

    def distance(self):
        GPIO.output(self.trigger, GPIO.LOW)
        time.sleep(0.01)
        GPIO.output(self.trigger, GPIO.HIGH)
        time.sleep(0.00001)
        GPIO.output(self.trigger, GPIO.LOW)

        timeout_start = time.monotonic()
        pulse_start = timeout_start

        while GPIO.input(self.echo) == 0:
            pulse_start = time.monotonic()
            if pulse_start - timeout_start > self.timeout:
                return -1

        pulse_end = pulse_start

        while GPIO.input(self.echo) == 1:
            pulse_end = time.monotonic()
            if pulse_end - timeout_start > self.timeout:
                return -1

        return round((pulse_end - pulse_start) * 343.0 * 100 / 2, 1)

    def get_distance(self, mount=5):
        distances = [self.distance() for _ in range(mount)]
        distances = [value for value in distances if value >= 0]
        if not distances:
            return -1
        return int(sum(distances) / len(distances))

    def less_than(self, alarm_gate):
        distance = self.get_distance()
        if distance < 0:
            return -1
        return 1 if distance <= alarm_gate else 0


def test():
    sensor = Ultrasonic_Avoidance(16, 12)
    while True:
        print(f"distance : {sensor.distance()} cm")
        time.sleep(0.2)


if __name__ == "__main__":
    test()
