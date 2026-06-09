% =========================================================================
% GÉNÉRATEUR DE VARIABLES POUR TRANSFORMATEUR D'ISOLEMENT (TI) 
% =========================================================================

% ---> CHOISIS LA PUISSANCE DU TI ICI (25, 45, 65, 150, 200 ou 300) <---
Puissance_TI_W = 300; 

% Paramètres généraux
f = 50; % Hz
I_nom = 6.6; % Courant nominal efficace (A)
I_peak = I_nom * sqrt(2); % Courant crête (A)

% -------------------------------------------------------------------------
% 1. INTERPOLATION DE L'INDUCTANCE DE FUITE (Basée sur Vidal et al.)
% -------------------------------------------------------------------------
% Données de référence expérimentales (Table 1)
P_ref  = [45, 150];         % Puissances en W
Ld_ref = [0.370, 1.19] * 1e-3; % Inductances de fuite en Henry

L_fuite = interp1(P_ref, Ld_ref, Puissance_TI_W, 'linear', 'extrap');


% Base de données des paramètres (OCEM / FAA)
switch Puissance_TI_W
    case 25
        Voc = 8; R = 0.060; Lm = 13e-3;
    case 45
        Voc = 13; R = 0.045; Lm = 16e-3;
    case 65
        Voc = 11; R = 0.065; Lm = 19e-3;
    case 150
        Voc = 25; R = 0.095; Lm = 24e-3;
    case 200
        Voc = 41; R = 0.125; Lm = 25e-3;
    case 300
        Voc = 70; R = 0.190; Lm = 35e-3;
    otherwise
        error('Puissance non reconnue.');
end

% % 1. Tensions nominales
V_nom = Puissance_TI_W / I_nom;
% 
% % 2. Calcul de la courbe de saturation
% lambda_max = (Voc * sqrt(2)) / (2 * pi * f);
% M1 = 1 / Lm; 
% P = 21; 
% M2 = (I_peak - (M1 * lambda_max)) / (lambda_max^P);
% 
% lambda_vec = linspace(0, lambda_max * 1.3, 100)'; 
% im_vec = M1 .* lambda_vec + M2 .* (lambda_vec.^P); 

% -------------------------------------------------------------------------
% 3. CARACTÉRISATION DE LA SATURATION (Modèle empirique de Vidal et al. 2015)
% -------------------------------------------------------------------------
% Paramètres expérimentaux (Table 1, TR 60 W)
M1 = Lm; % Henrys
M2 = 0.1e-3;  % Henrys
p_vid = 11;  % Facteur de forme du coude (sans unité)
i0 = 5.85;    % Courant de genou (Ampères)

% On crée un vecteur de courant allant de 0 à 15 Ampères (pour couvrir les pics)
im_vec = linspace(0, 15, 1000)'; 

% Application de l'équation (4) de Vidal pour obtenir l'inductance M(im)
M_im = (M1 ./ ((1 + (im_vec ./ i0).^p_vid).^(1/p_vid))) + M2;

% Calcul du flux magnétique (lambda = L * i)
lambda_vec = M_im .* im_vec;

% Injection dans la matrice Simulink
TI_OCEM.Sat = [im_vec, lambda_vec];
% =========================================================================
% CRÉATION DE LA STRUCTURE DE VARIABLES POUR SIMULINK
% =========================================================================

% On regroupe tout dans une structure nommée "TI_OCEM"
TI_OCEM.Pn_fn = [Puissance_TI_W, f];
TI_OCEM.W1    = [V_nom, R, L_fuite];
TI_OCEM.W2    = [V_nom, R, L_fuite];
TI_OCEM.Sat   = [im_vec, lambda_vec];
TI_OCEM.Rm    = 200; % Pertes fer génériques

disp('? Les variables TI_OCEM ont été chargées dans le Workspace avec succès !');
disp('Vous pouvez maintenant lancer la simulation Simulink.');
