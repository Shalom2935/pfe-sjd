t = t_end - T;
indices_i = (Is.Time >= t) & (Is.Time <= t_end);
indices = (Vs.Time >= t) & (Vs.Time <= t_end);
Vs_bout = Vs.Data(indices);
t_bout = Vs.Time(indices);
% Calcul du RMS sur ce petit bout
Integrale_V2 = trapz(t_bout, Vs_bout.^2);
Vrms = sqrt(Integrale_V2 / T);
Irms = sqrt(mean(Is.Data(indices_i).^2));

P_in  = mean(Vp.Data(indices) .* Ip.Data(indices_i)); % Puissance active absorbée au primaire
P_out = mean(Vs.Data(indices) .* Is.Data(indices_i)); % Puissance active restituée au secondaire

% 2. Calcul du rendement EXACT
Efficacite = (P_out / P_in) * 100;

disp(['Puissance absorbée (P_in) : ', num2str(P_in), ' W']);
disp(['Puissance restituée (P_out) : ', num2str(P_out), ' W']);
disp(['Rendement  : ', num2str(Efficacite), ' %']);
disp(['Vrms  : ', num2str(Vrms), ' V']);
disp(['Irms  : ', num2str(Irms), ' A']);
