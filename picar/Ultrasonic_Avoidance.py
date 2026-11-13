#!/usr/bin/env python3
import time

import RPi.GPIO as GPIO


class Ultrasonic_Avoidance(object):
    timeout = 0.05

    def __init__(self, channel=20):
        self.channel = channel
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)

    def distance(self):
        GPIO.setup(self.channel, GPIO.OUT)
        GPIO.output(self.channel, GPIO.LOW)
        time.sleep(0.01)
        GPIO.output(self.channel, GPIO.HIGH)
        time.sleep(0.00001)
        GPIO.output(self.channel, GPIO.LOW)
        GPIO.setup(self.channel, GPIO.IN)

        timeout_start = time.monotonic()
        pulse_start = timeout_start

        while GPIO.input(self.channel) == 0:
            pulse_start = time.monotonic()
            if pulse_start - timeout_start > self.timeout:
                return -1

        pulse_end = pulse_start

        while GPIO.input(self.channel) == 1:
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
    sensor = Ultrasonic_Avoidance(20)
    while True:
        print(f"distance : {sensor.distance()} cm")
        time.sleep(0.2)


if __name__ == "__main__":
    test()
