clear; close all; clc;

% Dossier de sortie des figures (a cote de ce script)
dossier_figures = fullfile(fileparts(mfilename('fullpath')), 'figures');
if ~exist(dossier_figures, 'dir')
    mkdir(dossier_figures);
end

distances_reelles = [1 2 3]; % mesurées à la règle (cm)
distances_mesurees = [1 2 3]; % mesurées par le capteur (cm)

% x = distance de reference (regle), y = lecture du capteur
x = distances_reelles(:);
y = distances_mesurees(:);

n = numel(x);

% --- Methode des equations normales ---
% On ajuste la reponse du capteur :
%   distance_mesuree = a * distance_reelle + b
% Sous forme matricielle : A*c = y, avec A = [x 1] et c = [a; b].
% Les equations normales sont : (A'*A)*c = A'*y.
A = [x ones(n, 1)];
c = (A' * A) \ (A' * y);

a = c(1);
b = c(2);

% Valeurs predites par la regression (distance mesuree estimee)
y_ajuste = a*x + b;

% Correction a appliquer sur une lecture du capteur :
%   distance_corrigee = (distance_mesuree - b) / a
alpha = 1/a;
beta = -b/a;
y_corrigee = alpha*y + beta;

% Erreurs et indicateurs de qualite de la regression
residus = y - y_ajuste;
SCE = sum(residus.^2);                  % somme des carres des erreurs
SCT = sum((y - mean(y)).^2);            % somme des carres totale
R2 = 1 - SCE/SCT;
RMSE = sqrt(mean(residus.^2));
erreur_max = max(abs(residus));

% Erreurs apres correction
residus_corriges = y_corrigee - x;
RMSE_corrige = sqrt(mean(residus_corriges.^2));
erreur_max_corrigee = max(abs(residus_corriges));

% Resultats dans la console
fprintf('\n===== RESULTAT DE L''AJUSTEMENT LINEAIRE (par équations normales) =====\n');
fprintf('Modele  : distance_mesuree = a * distance_reelle + b\n\n');
fprintf('  a = %.6f\n', a);
fprintf('  b = %.6f\n', b);
fprintf('  Equation : distance_mesuree = %.6f * distance_reelle %+.6f\n\n', a, b);
fprintf('  R^2       = %.4f\n', R2);
fprintf('  RMSE      = %.4f (cm)\n', RMSE);
fprintf('  Erreur max = %.4f\n\n', erreur_max);
fprintf('Correction a appliquer sur une lecture du capteur :\n');
fprintf('  distance_corrigee = (distance_mesuree - b) / a\n');
fprintf('                    = %.6f * distance_mesuree %+.6f\n', alpha, beta);
fprintf('  RMSE apres correction = %.4f cm (max %.4f)\n\n', RMSE_corrige, erreur_max_corrigee);

% Tableau des valeurs
fprintf(' Distance reelle |  Mesuree  |  Corrigee | Erreur (corr.-reelle)\n');
fprintf('-----------------+-----------+-----------+----------------------\n');
for i = 1:n
    fprintf(' %15.2f | %9.2f | %9.2f | %+9.2f\n', ...
        x(i), y(i), y_corrigee(i), residus_corriges(i));
end
fprintf('\n');

% Figure 1
fig1 = figure('Name', 'Mesures en fonction de la distance reelle', ...
              'Color', 'w', 'Position', [100 100 640 480]);
plot(x, y, 'o', 'MarkerSize', 7, 'LineWidth', 1.5);
hold on;
limite_max = max([x; y; y_ajuste; y_corrigee]);
limite_max = limite_max + 0.05*limite_max;
limites = [0 limite_max];
plot(limites, limites, 'k--', 'LineWidth', 1);
hold off;
grid on;
box on;
axis equal;
xlim(limites);
ylim(limites);
set(gca, 'FontSize', 12);
xlabel('Distance réelle (cm)');
ylabel('Distance mesurée par le capteur (cm)');
title('Mesures en fonction de la distance reelle');
legend('Mesures', 'Idéal (y = x)', 'Location', 'northwest');

fichier_fig1 = fullfile(dossier_figures, '1_valeurs_reelles_vs_mesurees.png');
print(fig1, fichier_fig1, '-dpng', '-r200');
close(fig1);

% Figure 2 : regression lineaire et mesures corrigees
x_droite = linspace(min(x), max(x), 100);

fig2 = figure('Name', 'Regression lineaire et mesures corrigees', ...
              'Color', 'w', 'Position', [100 100 640 480]);
plot(x, y, 'o', 'MarkerSize', 7, 'LineWidth', 1.5);
hold on;
plot(x_droite, a*x_droite + b, 'r-', 'LineWidth', 2);
plot(x, y_corrigee, 's', 'MarkerSize', 7, 'LineWidth', 1.5, ...
     'Color', [0.47 0.67 0.19]);
plot(limites, limites, 'k--', 'LineWidth', 1);
hold off;
grid on;
box on;
axis equal;
xlim(limites);
ylim(limites);
set(gca, 'FontSize', 12);
xlabel('Distance réelle (cm)');
ylabel('Distance mesurée et corrigée (cm)');
title('Régression linéaire et mesures corrigées');
% Troncature a 2 decimales uniquement pour l'affichage dans la legende
alpha_legende = fix(alpha*100)/100;
beta_legende = fix(beta*100)/100;
legende_regression = sprintf('Régression linéaire y=%.2fx%+.2f', a, b);
legende_correction = sprintf('Mesures corrigées par %.2fx%+.2f', ...
                             alpha_legende, beta_legende);
legend('Mesures', legende_regression, legende_correction, ...
       'Idéal (y = x)', 'Location', 'northwest');

fichier_fig2 = fullfile(dossier_figures, '2_ajustement_lineaire.png');
print(fig2, fichier_fig2, '-dpng', '-r200');
close(fig2);

fprintf('Figures enregistrees :\n  %s\n  %s\n\n', fichier_fig1, fichier_fig2);
