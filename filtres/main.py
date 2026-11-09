import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
from zplane import zplane

mesures_test = [30, 29, 28, 27, 32, 25, 24, 23, 86, 21, 20, 55, 18, 17, 16, 15, 14, 100, 12, 11, 89, 9, 8, 7, 6, 42, 4, 3, 2, 1]
print(len(mesures_test))
distances_reelles = list(range(30, 0, -1))

te = 0.06
fe = 1/te
n = 3

#filtre médian
def filtre_median(x, n=n):
    y = []
    for i in range(len(x)):
        fenetre = []
        for k in range(n):
            fenetre.append(x[max(i - k, 0)])
        y.append(float(np.median(fenetre)))
    return y

#filtre passe-bas
def filtre_passe_bas(x):
    y=[]
    precedant = x[0]
    for i in x:
        precedant = 0.5 * i + 0.5 * precedant
        y.append(precedant)
    return y

#filtre moyenne mobile
def filtre_moyenne_mobile(x, n=n):
    y = []
    for i in range(len(x)):
        fenetre = []
        for k in range(n):
            fenetre.append(x[max(i - k, 0)])
        y.append(sum(fenetre) / n)
    return y





y_median = filtre_median(mesures_test)
y_passe_bas = filtre_passe_bas(mesures_test)
y_moyenne_mobile = filtre_moyenne_mobile(mesures_test)

t = np.arange(len(mesures_test)) * te #temps du test

#réponse dans le temps
plt.figure()
plt.plot(t, mesures_test, "o-", color="lightgray", label="Mesures")
plt.plot(t, distances_reelles, "k--", linewidth=1, label="Distance réelle")
plt.plot(t, y_median, "o-", label="Médian")
plt.plot(t, y_passe_bas, "o-", label="Passe-bas")
plt.plot(t, y_moyenne_mobile, "o-", label="Moyenne mobile")
plt.xlabel("Temps [s]")
plt.ylabel("Distance [cm]")
plt.title("Filtre des mesures du capteur de distance")
plt.grid(True)
plt.legend()
plt.tight_layout()
plt.show()


#réponse en fréquence du passe-bas
#coefficients du passe-bas : H(z) = 0.5 / (1 - 0.5 z^-1)
b = [0.5, 0]
a = [1, -0.5]
zplane(b, a)

w, h = signal.freqz(b, a, worN=500)
h_db = 20 * np.log10(np.abs(h))

#fc: point où l'amplitude du signal est multipliée par 1/sqrt(2)
#db: 20log10(0,707) = -3 dB
wc = w[np.argmin(np.abs(h_db + 3))]
fc = wc / (2 * np.pi) * fe
print(f"Fréquence de coupure : {wc:.2f} rad/éch. = {fc:.2f} Hz")

plt.figure()
plt.plot(w, h_db)
plt.axhline(-3, color="red", linestyle="--")
plt.title("Réponse en fréquence : passe-bas")
plt.xlabel("Fréquence [rad/éch.]")
plt.ylabel("Amplitude [dB]")
plt.grid(True)
plt.show()




"""
#ancien code pas bon (gardé au cas où)

Fe = 60000
Wp = [24000 / (Fe / 2), 26000 / (Fe / 2)]
Ws = [23000 / (Fe / 2), 27000 / (Fe / 2)]
Rp = 0.5
Rs = 40

#chebyshev type 2
b_ord, Wn = signal.cheb2ord(Wp, Ws, Rp, Rs)
print(b_ord, Wn)

num, den = signal.cheby2(b_ord, Rs, Wn, 'bandpass')
print("cheby II: ", num, den)
plt.figure()
zplane(num, den)

w, h = signal.freqz(num, den)
plt.figure()
plt.title('Réponse en fréquence : Chebyshev type 2')
plt.plot(w, 20 * np.log10(abs(h)))
plt.ylabel('Amplitude [dB]')
plt.hlines(0.5, 0, max(w), color='r', linestyles='--')
plt.hlines(-40, 0, max(w), color='r', linestyles='--')
plt.ylabel('Amplitude [dB]')
plt.xlabel('Fréquence [rad/éch.]')
plt.axis('tight')
plt.grid()
plt.show()

#elliptique
b_ord, Wn = signal.ellipord(Wp, Ws, Rp, Rs)
print(b_ord)

num, den = signal.ellip(b_ord, Rp, Rs, Wn, 'bandpass')
print("ellip: ", num, den)
plt.figure()
zplane(num, den)

w, h = signal.freqz(num, den)
fig = plt.figure()
plt.title('Réponse en fréquence : elliptique')
plt.plot(w, 20 * np.log10(abs(h)))
plt.hlines(0.5, 0, max(w), color='r', linestyles='--')
plt.hlines(-40, 0, max(w), color='r', linestyles='--')
plt.ylabel('Amplitude [dB]')
plt.xlabel('Fréquence [rad/éch.]')
plt.axis('tight')
plt.grid()
plt.show()
"""