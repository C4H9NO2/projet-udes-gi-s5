## Nettoyage du projet de départ

Modifications faites sur le projet du site de session :

- Ajout de fichiers dans le `.gitignore`
  - `*.blend1` : sauvegardes automatiques de Blender
  - `*.tmp` : fichiers temporaires de Godot
  - `.DS_Store`, `Thumbs.db` : fichiers système macOS / Windows
- Fichiers retirés du projet :
  - tmp (`mai*.tmp`, `lin*.tmp`) retirés du git
  - Fichiers `.glb.import` : `Cybertruck.glb.import` et `plaquette_blender_scale.glb.import` pointaient vers des `.glb` absents du projet
  - `.gitmodules` supprimé : déclarait des sous-modules git inexistants (`finite_state_machine` est déjà inclus dans `addons/`).
- **Fichiers ajoutés dans le git**
  - Modèles blender de `assets/` (`Cybertruck.blend`, `obstacle.blend`, `parcours.blend`, `plaquette_blender_scale.blend`) et leurs fichiers `.import`
  - Fichiers `.uid` des scripts (ça les prend depuis Godot 4.4 pour que les références entre fichiers fonctionnent)

## Prérequis

- **Godot 4.4.1** (version standard, pas .NET) on utilise la même version pour pas avoir de problèmes de compatibilité
- **Blender** si vous modifiez les modèles `.blend`, il faut mettre son path dans *Éditeur → Paramètres de l'éditeur → FileSystem → Import → Blender*

## NB
(voir `scripts/fsm/NetworkConnectingState.gd`) si jamais, Godot se connecte au serveur WebSocket sur le raspberry pi sur le port **8765** (so l'ordi doit être sur le même réseau que le pi)
