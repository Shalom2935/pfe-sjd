function TI_DB = FullLoop_TI_database()
%FULLLOOP_TI_DATABASE Validated OCEM isolation-transformer parameter table.
%
% The Simulink model in model/OCEM_TI is generic. Its parameters were tuned
% manually power range by power range; this file centralizes the final values
% so complete-loop simulations no longer depend on hard-coded block edits.
%
% LEAKAGE INDUCTANCE:
% Ldp = Lds is obtained from the experimental reference points used during
% TI validation:
%   P_ref  = [45, 150] W
%   Ld_ref = [0.370, 1.19] mH
% and interpolated/extrapolated linearly for each nominal power.

    Power_W = [25; 45; 65; 150; 200; 300];

    EfficiencyMin_pct = [70; 85; 85; 90; 90; 90];
    LossesMax_W = [10.0; 7.9; 11.4; 16.6; 22.2; 33.3];
    WindingResistance_ohm = [0.060; 0.045; 0.065; 0.095; 0.125; 0.190];

    Leakage_mH = interp1([45; 150], [0.370; 1.190], Power_W, ...
                         'linear', 'extrap');

    LinearMagnetizationLm_mH = [13.0; 16.0; 19.0; 24.0; 25.0; 35.0];
    OpenCircuitVoltageTheoretical_V = [8; 13; 16; 25; 41; 70];
    OpenCircuitVoltageModel_V = [8.39; 12.45; 16.23; 27.2; 40.17; 45.53];

    SaturationM1_mH = [13; 16; 19; 24; 25; 35];
    SaturationM2_mH = [0.1; 0.1; 0.1; 0.1; 0.1; 0.1];
    SaturationI0_A = [1.31; 1.92; 2.33; 4.26; 5.46; 5.85];
    SaturationP = [1.7; 1.7; 1.7; 1.7; 6; 11];

    TI_DB = table(Power_W, EfficiencyMin_pct, LossesMax_W, ...
        WindingResistance_ohm, Leakage_mH, ...
        LinearMagnetizationLm_mH, OpenCircuitVoltageTheoretical_V, ...
        OpenCircuitVoltageModel_V, SaturationM1_mH, SaturationM2_mH, ...
        SaturationI0_A, SaturationP);
end
