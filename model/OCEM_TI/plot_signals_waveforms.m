% Définition de la fenêtre de temps à observer
f = 50;
T = 1/f;
t_start = 0.01; 
t_end = 0.1; 


figure('Color', 'white', 'Position', [100, 100, 800, 600]);

% --- SOUS-GRAPHIQUE 1 : TENSIONS ---
ax1 = subplot(2,1,1);
plot(Vp.Time, Vp.Data, 'k', 'LineWidth', 1.5); hold on; % Vp en Noir
plot(Vs.Time, Vs.Data, 'b', 'LineWidth', 1.5); % Vs en Bleu
grid on;
xlim([t_start, t_end]);
ylabel('Tension (V)', 'FontSize', 12, 'FontWeight', 'bold');
title('Réponse Temporelle du Transformateur OCEM 65W (Court-circuit)', 'FontSize', 14);
legend('V_p (Primaire)', 'V_s (Secondaire)', 'Location', 'northeast');
set(gca, 'FontSize', 11);

% --- SOUS-GRAPHIQUE 2 : COURANTS ---
ax2 = subplot(2,1,2);
plot(Ip.Time, Ip.Data, 'k', 'LineWidth', 1.5); hold on; % Ip en Noir
plot(Is.Time, Is.Data, 'b--', 'LineWidth', 1.5); % Is en Bleu pointillé
grid on;
xlim([t_start, t_end]);
xlabel('Temps (s)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Courant (A)', 'FontSize', 12, 'FontWeight', 'bold');
legend('i_p (Primaire)', 'i_s (Secondaire)', 'Location', 'northeast');
set(gca, 'FontSize', 11);

% Lier l'axe X des deux graphiques (si on zoome sur l'un, l'autre zoome aussi)
linkaxes([ax1, ax2], 'x');
