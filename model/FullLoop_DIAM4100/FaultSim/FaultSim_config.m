function cfg = FaultSim_config(varargin)
%FAULTSIM_CONFIG Central configuration for DIAM4100 full-loop fault simulations.
%
% This file centralizes every value that conditions a long simulation campaign.
% Do not bury physical or ML parameters in other scripts.
%
% Usage:
%   cfg = FaultSim_config()
%   cfg = FaultSim_config('Mode','smoke')
%   cfg = FaultSim_config('Mode','full','AcceptUnvalidatedRanges',true)

    parser = inputParser;
    parser.addParameter('Mode', 'full', @(s)ischar(s) || isstring(s));
    parser.addParameter('AcceptUnvalidatedRanges', false, @(x)islogical(x) && isscalar(x));
    parser.parse(varargin{:});

    cfg = struct();
    cfg.mode = char(parser.Results.Mode);
    cfg.acceptUnvalidatedRanges = parser.Results.AcceptUnvalidatedRanges;

    thisFile = mfilename('fullpath');
    cfg.paths.faultSimDir = fileparts(thisFile);
    cfg.paths.fullLoopDir = fileparts(cfg.paths.faultSimDir);
    cfg.paths.outputDir = fullfile(cfg.paths.fullLoopDir, 'outputs', 'FaultSim');
    cfg.paths.rawDir = fullfile(cfg.paths.outputDir, 'raw', lower(cfg.mode));
    cfg.paths.featureDir = fullfile(cfg.paths.outputDir, 'features');
    cfg.paths.metadataDir = fullfile(cfg.paths.outputDir, 'metadata');
    cfg.paths.logDir = fullfile(cfg.paths.outputDir, 'logs');

    cfg.model.originalName = 'AGL_FullLoop_DIAM4100';
    cfg.model.faultName = 'AGL_FullLoop_DIAM4100_faultsim';
    cfg.model.originalFile = fullfile(cfg.paths.fullLoopDir, [cfg.model.originalName '.slx']);
    cfg.model.faultFile = fullfile(cfg.paths.fullLoopDir, [cfg.model.faultName '.slx']);

    % Export sampling requested for ML dataset.
    cfg.fs_Hz = 10000;
    cfg.Ts_s = 1 / cfg.fs_Hz;

    % Simulation horizon.
    % The DIAM4100 Ki sweep showed settling times up to about 0.9 s. We
    % therefore simulate up to 1.10 s and keep only the final stable 0.10 s
    % window, i.e. about 5 periods at 50 Hz.
    cfg.simTime_s = 1.10;
    cfg.rawSaveWindow_s = 0.10;
    cfg.featureWindow_s = 0.10;
    cfg.gridFrequency_Hz = 50;

    % Normal mode is used intentionally. Rapid Accelerator is disabled.
    cfg.execution.simulationMode = 'normal';

    % Fault-location resolution.
    cfg.locationStep_m = 60;

    % Fault inactive / nominal values.
    cfg.inactiveShuntR_ohm = 1e12;
    cfg.inactiveShuntC_F = 1e-15;
    cfg.normalSeriesR_ohm = 1e-6;

    % Extreme values used for load-fault class only.
    cfg.loadOpenR_ohm = 1e9;
    cfg.loadShortR_ohm = 1e-3;

    % Harmonic features to extract from u_RCC and i_RCC.
    cfg.features.harmonics = [1 3 5 7 9 11 13 15 17 19];

    % Required and optional exported variables.
    cfg.signals.required = {'u_RCC', 'i_RCC'};
    cfg.signals.optional = { ...
        'DIAM4100_Irms', ...
        'FullLoop_I_MEAS_001', ...
        'FullLoop_I_MEAS_010', ...
        'FullLoop_I_MEAS_020', ...
        'FullLoop_I_MEAS_030', ...
        'FullLoop_I_MEAS_040', ...
        'FullLoop_I_MEAS_050', ...
        'FullLoop_I_MEAS_051'};

    % Brightness indices used by the existing DIAM4100 scripts: B0=1 ... B5=6.
    cfg.smoke.brightnessList = 6;
    cfg.full.brightnessList = 1:6;

    % Smoke mode: one or two examples per class, enough to validate wiring.
    cfg.smoke.maxScenarios = 16;

    % Full mode location stride. Keep 1 for 60 m resolution.
    cfg.full.locationStride = 1;

    % ---------------------------------------------------------------------
    % Fault severity ranges.
    % ---------------------------------------------------------------------
    % These ranges are centralized and traceable. They are deliberately not
    % hidden inside the scenario generator. Review them before long runs.
    %
    % Humidity and TI leakage are modeled as leakage resistance to earth.
    % Reactive incipient faults are modeled as extra capacitance to earth.
    % Earth and surge faults are modeled as low-resistance shunts to earth.
    % Open-circuit faults are modeled as high series resistance.
    %
    % The full batch refuses to run unless AcceptUnvalidatedRanges=true.
    cfg.ranges.humidity_R_ohm = [20e6 10e6 5e6 1e6 250e3];
    cfg.ranges.reactive_C_F = [0.5e-9 1e-9 2e-9 5e-9 10e-9];
    cfg.ranges.earth_short_R_ohm = [100 30 10 3 1];
    cfg.ranges.surge_short_R_ohm = [30 10 3 1];
    cfg.ranges.ti_leakage_R_ohm = [20e6 10e6 5e6 1e6 250e3];
    cfg.ranges.open_series_R_ohm = [1e5 1e6 1e7 1e8];
    cfg.ranges.loadFaultModes = {'open', 'short'};

    % Class dictionary.
    cfg.classes = table( ...
        [0;1;2;3;4;5;6;7], ...
        {'HEALTHY'; 'HUMIDITY_PROGRESSIVE'; 'REACTIVE_INCIPIENT'; ...
         'EARTH_SHORT'; 'SURGE_ARRESTER_SHORT'; 'TI_INSULATION_LEAKAGE'; ...
         'OPEN_CIRCUIT'; 'TI_LOAD_FAULT'}, ...
        {'healthy'; 'insulation_fault'; 'insulation_fault'; ...
         'insulation_fault'; 'insulation_fault'; 'insulation_fault'; ...
         'continuity_fault'; 'non_insulation_load_fault'}, ...
        {'healthy'; 'high_R_resistive_leakage'; 'capacitive_leakage'; ...
         'low_R_earth_fault'; 'low_R_earth_fault'; 'high_R_resistive_leakage'; ...
         'series_open'; 'secondary_load_fault'}, ...
        [false; true; true; true; true; true; false; false], ...
        'VariableNames', {'class_id','class_name','fault_group','electrical_fault_family','is_insulation_fault'});
end
