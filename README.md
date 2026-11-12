# Modifs faites sur les fichiers de départ du site de session
Les deux dossiers du site de session sont regroupés dans un seul dépôt, `Dossier_GoDot/` → `godot/` et `Dossier_PiCar/` → `picar/`

## GoDot : 
- Ajoutés au `.gitignore` :
  - `*.blend1` : sauvegardes automatiques de Blender
  - `*.tmp` : fichiers temporaires de Godot
  - `.DS_Store`, `Thumbs.db` : fichiers système macOS / Windows
- Retirés du projet :
  - tmp (`mai*.tmp`, `lin*.tmp`) retirés du git
  - Fichiers `.glb.import` : `Cybertruck.glb.import` et `plaquette_blender_scale.glb.import` pointaient vers des `.glb` absents du projet
  - `.gitmodules` supprimé : déclarait des sous-modules git inexistants (`finite_state_machine` est déjà inclus dans `addons/`).
- Ajoutés au git :
  - Modèles blender de `assets/` (`Cybertruck.blend`, `obstacle.blend`, `parcours.blend`, `plaquette_blender_scale.blend`) et leurs fichiers `.import`
  - Fichiers `.uid` des scripts (ça les prend depuis Godot 4.4 pour que les références entre fichiers fonctionnent)
 
## PiCar
- Ajoutés au `.gitignore` :
  - `__pycache__/`, `*.py[cod]`, `build/`, `dist/`, `*.egg-info/` : fichiers Python générés
  - `.venv/`, `venv/`
  - `picar/Godot/` : exécutable Godot pour le Pi
  - `sftp.json` : config SFTP de VSCode (contient un mdp)
- Retirés du projet :
  - `picar/.venv/` : environnement Python du Pi du prof, remplacé par `requirements.txt`
  - `picar/Godot/Godot_executable/` : Godot 4.2.1 ARM 32 bits (87 Mo)
  - Dossiers `.git` et `.gitmodules` de `SunFounder_PiCar/` et `SunFounder_PiCar-S/` (code gardé, juste enlevé les historiques git)
  - `SunFounder_PiCar/build/`, `dist/`, `SunFounder_PiCar.egg-info/`, `__pycache__/` : fichiers générés
  - `SunFounder_PiCar/.vscode/sftp.json` retiré du git (contient l'IP du Pi du prof et le mdp `pi`/`raspberry`)
- Ajoutés au git :
  - `picar/requirements.txt` : versions trouvées dans le `.venv` du prof (`websockets==12.0`, `RPi.GPIO==0.7.1`, `pigpio==1.78`, `smbus==1.1.post2`)

## Prérequis

- **Godot 4.4.1** (version standard, pas .NET) on utilise la même version pour pas avoir de problèmes de compatibilité
- **Blender** si vous modifiez les modèles `.blend`, il faut mettre son path dans *Éditeur → Paramètres de l'éditeur → FileSystem → Import → Blender*
- **Sur le Pi** (recréer le .venv sur le raspberry pi) : `cd picar && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt ./SunFounder_PiCar ./SunFounder_PiCar-S` puis `./.venv/bin/python main.py` pour lancer le serveur WebSocket du PiCar 

## NB
- (voir `godot/scripts/fsm/NetworkConnectingState.gd`) si jamais, Godot se connecte au serveur WebSocket sur le raspberry pi sur le port **8765** (so l'ordi doit être sur le même réseau que le pi)
- Le dossier du site de session contenait un exécutable Godot 4.2.1 pour le Pi sauf que le projet est en **4.4**. Va falloir demander au prof quelle version utiliser quand on va faire rouler GoDot sur le raspberry pi
