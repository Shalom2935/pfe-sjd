% DIAM4100_SIMPARAMS
% Centralized parameters for CCR_DIAM4100_model.slx.
%
% Optional overrides:
%   DIAM4100_user.ratings.ratedPower_kVA = 10;
%   DIAM4100_user.load.effectivePower_VA = 2442;
%   DIAM4100_user.control.activeBrightness = 6; % index in brightness table
%   run DIAM4100_simParams

thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);
addpath(thisDir);

cfg = struct();

% Nameplate and supply.
cfg.model.name = 'CCR_DIAM4100_model';
cfg.ratings.ratedPower_kVA = 10;
cfg.ratings.outputCurrentMax_Arms = 6.6;
cfg.grid.Vrms = 230;
cfg.grid.f_Hz = 50;

% DIAM4100 preferred brightness values, including B0.
cfg.control.brightnessLabels = {'B0','B1','B2','B3','B4','B5'};
cfg.control.brightnessCurrents_Arms = [1.50 2.80 3.40 4.10 5.20 6.60];
cfg.control.activeBrightness = 6;
cfg.control.currentTolerance_A = 0.10;

% Douala loop operating point.
% The 4/8 load tap is justified by the installed TI capacity, while the
% nominal electrical load used in the CCR model is the LED load sum.
cfg.loadTap.eighths = 4;
cfg.load.ledNominalPower_VA = 2442;
cfg.load.ledNominalResistance_ohm = 56.06;
cfg.load.totalIsolationTransformerPower_W = 4485;
cfg.load.effectivePower_VA = cfg.load.ledNominalPower_VA;

% Controller. Ki is scheduled below.
cfg.control.Kp = 0.1;
cfg.control.Ts_s = 1e-4;
cfg.control.alphaMin_deg = 0;
cfg.control.alphaMax_deg = 180;
cfg.control.alphaOffset_deg = 180;
cfg.control.integratorIC_deg = 5;
cfg.control.KiAtNominalLoad = 200;
cfg.control.KiMin = 60;
cfg.control.KiMax = 300;
cfg.control.KiLoadExponent = 0.65;
cfg.control.KiBrightnessExponent = 0.10;

% Power electronics and measurement.
cfg.thyristor.Ron_ohm = 1e-3;
cfg.thyristor.Lon_H = 0;
cfg.thyristor.Vf_V = 0.8;
cfg.thyristor.Rs_ohm = 500;
cfg.thyristor.Cs_F = 250e-9;
cfg.pulse.pwidth_deg = 60;
cfg.powergui.Ts_s = 50e-6;

% Transformer model values kept from the current Simulink model.
cfg.transformer.windingResistance_pu = 0.01;
cfg.transformer.windingLeakage_pu = 0.03;
cfg.transformer.RmLm_pu = [500 500];

% Resistive load placeholder. Cable/TI/LED models will replace this later.
cfg.load.L_H = 1e-3;
cfg.load.C_F = 1e-6;

% Validation requirements used by DIAM4100_validateControl.
cfg.norms.IEC.settlingTime_s = 0.5;
cfg.norms.IEC.maxStepOvershoot_Arms = 6.7;
cfg.norms.IEC.dynamicOvercurrentHalfCycle_s = 1 / (2 * cfg.grid.f_Hz);
cfg.norms.FAA.controlSettlingTime_s = 5.0;
cfg.norms.FAA.currentTolerance_A = 0.10;
cfg.norms.FAA.maxTransientRatio = 1.20;
cfg.norms.FAA.maxTransientDuration_s = 0.250;

if exist('DIAM4100_user', 'var') == 1
    cfg = localMergeStruct(cfg, DIAM4100_user);
end

DIAM4100 = cfg;

DIAM4100.grid.Vpk = sqrt(2) * DIAM4100.grid.Vrms;
DIAM4100.ratings.ratedPower_VA = 1000 * DIAM4100.ratings.ratedPower_kVA;

DIAM4100.loadTap.factor = DIAM4100.loadTap.eighths / 8;
DIAM4100.loadTap.availablePower_kVA = DIAM4100.ratings.ratedPower_kVA * ...
                                       DIAM4100.loadTap.factor;
DIAM4100.loadTap.marginVsTiPower_pct = 100 * ...
    ((1000 * DIAM4100.loadTap.availablePower_kVA) - ...
     DIAM4100.load.totalIsolationTransformerPower_W) / ...
    DIAM4100.load.totalIsolationTransformerPower_W;
DIAM4100.loadTap.outputVoltageAtMaxCurrent_Vrms = ...
    (1000 * DIAM4100.loadTap.availablePower_kVA) / ...
    DIAM4100.ratings.outputCurrentMax_Arms;

DIAM4100.load.nominalRatio = DIAM4100.load.effectivePower_VA / ...
                              DIAM4100.load.ledNominalPower_VA;
DIAM4100.load.R_ohm = DIAM4100.load.effectivePower_VA / ...
                      (DIAM4100.ratings.outputCurrentMax_Arms^2);

activeBrightness = DIAM4100.control.activeBrightness;
DIAM4100.control.activeBrightnessLabel = DIAM4100.control.brightnessLabels{activeBrightness};
DIAM4100.control.Iref_Arms = DIAM4100.control.brightnessCurrents_Arms(activeBrightness);
DIAM4100.control.currentMin_Arms = DIAM4100.control.Iref_Arms - ...
                                   DIAM4100.control.currentTolerance_A;
DIAM4100.control.currentMax_Arms = DIAM4100.control.Iref_Arms + ...
                                   DIAM4100.control.currentTolerance_A;

DIAM4100.control.schedule.currentGrid_Arms = DIAM4100.control.brightnessCurrents_Arms;
DIAM4100.control.schedule.loadPowerGrid_VA = DIAM4100.load.ledNominalPower_VA * ...
                                             [0.20 0.35 0.50 0.75 1.00 1.20];
DIAM4100.control.schedule.KiTable = localBuildScheduleTable(DIAM4100);
DIAM4100.control.Ki = DIAM4100_gainSchedule(DIAM4100.control.Iref_Arms, ...
                                            DIAM4100.load.effectivePower_VA, ...
                                            DIAM4100.control.schedule);

DIAM4100.transformer.NominalPower = [DIAM4100.ratings.ratedPower_VA DIAM4100.grid.f_Hz];
DIAM4100.transformer.winding1 = [DIAM4100.grid.Vrms ...
                                 DIAM4100.transformer.windingResistance_pu ...
                                 DIAM4100.transformer.windingLeakage_pu];
DIAM4100.transformer.winding2 = [DIAM4100.loadTap.outputVoltageAtMaxCurrent_Vrms ...
                                 DIAM4100.transformer.windingResistance_pu ...
                                 DIAM4100.transformer.windingLeakage_pu];
DIAM4100.transformer.RmLm = DIAM4100.transformer.RmLm_pu;

DIAM4100.validation.simTime_s = 1.0;
DIAM4100.validation.outputCsv = fullfile(thisDir, 'DIAM4100_validation_results.csv');

assignin('base', 'DIAM4100', DIAM4100);

fprintf(['DIAM4100 loaded: %s, %g kVA, tap %d/8, %s = %.2f Arms, ' ...
         'load = %.0f VA, R = %.2f ohm, Ki = %.3g\n'], ...
        DIAM4100.model.name, ...
        DIAM4100.ratings.ratedPower_kVA, ...
        DIAM4100.loadTap.eighths, ...
        DIAM4100.control.activeBrightnessLabel, ...
        DIAM4100.control.Iref_Arms, ...
        DIAM4100.load.effectivePower_VA, ...
        DIAM4100.load.R_ohm, ...
        DIAM4100.control.Ki);

function KiTable = localBuildScheduleTable(DIAM4100)
    Igrid = DIAM4100.control.schedule.currentGrid_Arms;
    loadGrid = DIAM4100.control.schedule.loadPowerGrid_VA;
    KiTable = zeros(numel(Igrid), numel(loadGrid));
    Iref = DIAM4100.ratings.outputCurrentMax_Arms;
    loadRef = DIAM4100.load.ledNominalPower_VA;

    for ii = 1:numel(Igrid)
        for jj = 1:numel(loadGrid)
            currentFactor = (Iref / Igrid(ii))^DIAM4100.control.KiBrightnessExponent;
            loadFactor = (loadGrid(jj) / loadRef)^DIAM4100.control.KiLoadExponent;
            KiTable(ii, jj) = min(max(DIAM4100.control.KiAtNominalLoad * ...
                currentFactor * loadFactor, DIAM4100.control.KiMin), ...
                DIAM4100.control.KiMax);
        end
    end
end

function out = localMergeStruct(out, in)
    names = fieldnames(in);
    for k = 1:numel(names)
        name = names{k};
        if isstruct(in.(name)) && isfield(out, name) && isstruct(out.(name))
            out.(name) = localMergeStruct(out.(name), in.(name));
        else
            out.(name) = in.(name);
        end
    end
end
