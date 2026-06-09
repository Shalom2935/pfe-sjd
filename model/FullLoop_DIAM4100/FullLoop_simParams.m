% FULLLOOP_SIMPARAMS
% Centralized parameters for the complete AGL loop model.
%
% This file intentionally lives in model/FullLoop_DIAM4100 so the complete
% loop can evolve without modifying the validated DIAM4100 and OCEM_TI
% development folders.

thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);
addpath(thisDir);

FullLoop = struct();

% -------------------------------------------------------------------------
% Global electrical settings.
% -------------------------------------------------------------------------
FullLoop.model.name = 'AGL_FullLoop_DIAM4100';
FullLoop.grid.f_Hz = 50;
FullLoop.loop.I_nom_Arms = 6.6;
FullLoop.loop.length_m = 9007;
FullLoop.loop.regardSpacing_m = 60;
FullLoop.loop.equippedRegardCount = 49;
FullLoop.loop.activeSpan_m = (FullLoop.loop.equippedRegardCount - 1) * ...
                             FullLoop.loop.regardSpacing_m;
FullLoop.loop.rccToFirstRegard_m = ...
    (FullLoop.loop.length_m - FullLoop.loop.activeSpan_m) / 2;
FullLoop.loop.rccToLastRegard_m = FullLoop.loop.rccToFirstRegard_m;
% Backward-compatible aliases: these refer to equipped regards only, not to
% an artificial 60 m grid over the complete 9007 m loop.
FullLoop.loop.nominalManholeSpacing_m = FullLoop.loop.regardSpacing_m;
FullLoop.loop.manholeCount = FullLoop.loop.equippedRegardCount;
FullLoop.loop.measureEveryNLoads = 10;

% Cable values taken from the existing Cable.slx pi-section line model.
% The block uses ohm/km, H/km and F/km.
FullLoop.cable.R_ohm_per_km = 3.928;
FullLoop.cable.L_H_per_km = 0.52e-3;
FullLoop.cable.C_F_per_km = 0.12e-6;

% -------------------------------------------------------------------------
% DIAM4100 equivalent source for the first complete-loop assembly.
% The detailed SCR model remains in model/DIAM4100 and can replace this
% module once the loop topology is stable.
% -------------------------------------------------------------------------
FullLoop.diam4100.sourceMode = 'equivalentCurrentSource';
FullLoop.diam4100.current_Arms = FullLoop.loop.I_nom_Arms;
FullLoop.diam4100.currentPeak_A = sqrt(2) * FullLoop.diam4100.current_Arms;
FullLoop.diam4100.phase_deg = 90;
FullLoop.diam4100.useDetailedModel = true;
FullLoop.diam4100.activeBrightness = 6;
FullLoop.diam4100.brightnessLabels = {'B0','B1','B2','B3','B4','B5'};
FullLoop.diam4100.brightnessCurrents_Arms = [1.50 2.80 3.40 4.10 5.20 6.60];
FullLoop.diam4100.kiScheduleCsv = fullfile(thisDir, '..', 'DIAM4100', ...
    'figures', 'DIAM4100_Ki_best_schedule.csv');
FullLoop.diam4100.referenceLoadPower_VA = 2442;

% -------------------------------------------------------------------------
% Isolation transformer parameter database.
% The OCEM TI Simulink model is generic; final values are centralized here
% from the validation table supplied in the Jumeau Numerique document.
% -------------------------------------------------------------------------
FullLoop.ti.database = FullLoop_TI_database();
FullLoop.ti.Rm_ohm = 200;
FullLoop.ti.saturation.currentVector_A = linspace(0, 15, 1000)';

% -------------------------------------------------------------------------
% Load inventory.
% Secondary load power is the useful fixture power at 6.6 A unless a more
% precise datasheet value is available.
% -------------------------------------------------------------------------
fixtureGroups = [
    struct('Prefix', 'F65', 'Count', 3,  'FixturePower_VA', 65, 'TIPower_W', 150, 'Kind', 'runway_light')
    struct('Prefix', 'F39', 'Count', 23, 'FixturePower_VA', 39, 'TIPower_W', 65,  'Kind', 'runway_light')
    struct('Prefix', 'F8',  'Count', 13, 'FixturePower_VA', 8,  'TIPower_W', 25,  'Kind', 'runway_light')
    struct('Prefix', 'F23', 'Count', 6,  'FixturePower_VA', 23, 'TIPower_W', 65,  'Kind', 'runway_light')
    struct('Prefix', 'F22', 'Count', 2,  'FixturePower_VA', 22, 'TIPower_W', 65,  'Kind', 'runway_light')
];

loads = struct('Name', {}, 'Kind', {}, 'FixturePower_VA', {}, ...
               'TIPower_W', {}, 'SecondaryResistance_ohm', {}, ...
               'RegardIndex', {}, 'ManholeIndex', {}, 'Distance_m', {});

for g = 1:numel(fixtureGroups)
    group = fixtureGroups(g);
    for k = 1:group.Count
        loads(end+1) = localMakeLoad( ... %#ok<SAGROW>
            sprintf('%s_%02d', group.Prefix, k), ...
            group.Kind, ...
            group.FixturePower_VA, ...
            group.TIPower_W, ...
            FullLoop.loop.I_nom_Arms);
    end
end

% Two wind cones, each supplied through two 45 W isolation transformers.
% The secondary load is initially set equal to the transformer rating because
% the exact local wind-cone secondary datasheet is not yet confirmed.
for wc = 1:2
    for branch = 1:2
        loads(end+1) = localMakeLoad( ... %#ok<SAGROW>
            sprintf('WINDCONE_%02d_TI_%d', wc, branch), ...
            'wind_cone_secondary_assumption', ...
            45, ...
            45, ...
            FullLoop.loop.I_nom_Arms);
    end
end

FullLoop.loads = localAssignEquippedRegards(loads, FullLoop.loop);
FullLoop.tiModules = localBuildTIModules(FullLoop.loads, FullLoop.ti, FullLoop.grid.f_Hz);

% Fifteen surge arresters distributed along the loop. They are represented
% by a very high resistance in normal operation, with a TODO path for a
% nonlinear MOV characteristic once the datasheet is fixed.
FullLoop.surge.count = 15;
FullLoop.surge.normalResistance_ohm = 1e9;
FullLoop.surge.strikeVoltage_V = 1000;
FullLoop.surge.regardIndex = round(linspace(1, FullLoop.loop.equippedRegardCount, ...
                                            FullLoop.surge.count));
FullLoop.surge.manholeIndex = FullLoop.surge.regardIndex;
FullLoop.surge.distance_m = FullLoop.loop.rccToFirstRegard_m + ...
    (FullLoop.surge.regardIndex - 1) * FullLoop.loop.regardSpacing_m;

FullLoop.summary.loadModuleCount = numel(FullLoop.loads);
FullLoop.summary.lightCount = 47;
FullLoop.summary.windConeCount = 2;
FullLoop.summary.windConeTIcount = 4;
FullLoop.summary.equippedRegardCount = FullLoop.loop.equippedRegardCount;
FullLoop.summary.totalSecondaryPower_VA = sum([FullLoop.loads.FixturePower_VA]);
FullLoop.summary.totalTIPower_W = sum([FullLoop.loads.TIPower_W]);

segmentLengths_m = [ ...
    FullLoop.loop.rccToFirstRegard_m, ...
    FullLoop.loop.regardSpacing_m * ones(1, FullLoop.loop.equippedRegardCount - 1), ...
    FullLoop.loop.rccToLastRegard_m];
FullLoop.segments.length_m = segmentLengths_m;
FullLoop.segments.length_km = segmentLengths_m / 1000;
FullLoop.segments.count = numel(segmentLengths_m);

FullLoop.validation.simTime_s = 0.25;
FullLoop.validation.outputPrefix = fullfile(thisDir, 'outputs', FullLoop.model.name);

assignin('base', 'FullLoop', FullLoop);

fprintf(['FullLoop loaded: %d load modules, %.0f VA secondary, %.0f W TI, ' ...
         '%.0f m cable, %d equipped regards.\n'], ...
        FullLoop.summary.loadModuleCount, ...
        FullLoop.summary.totalSecondaryPower_VA, ...
        FullLoop.summary.totalTIPower_W, ...
        FullLoop.loop.length_m, ...
        FullLoop.loop.equippedRegardCount);

function load = localMakeLoad(name, kind, fixturePower_VA, tiPower_W, I_nom)
    load = struct();
    load.Name = name;
    load.Kind = kind;
    load.FixturePower_VA = fixturePower_VA;
    load.TIPower_W = tiPower_W;
    load.SecondaryResistance_ohm = fixturePower_VA / (I_nom^2);
    load.RegardIndex = NaN;
    load.ManholeIndex = NaN;
    load.Distance_m = NaN;
end

function loads = localAssignEquippedRegards(loads, loop)
    regardIndex = 0;
    currentWindCone = '';
    for k = 1:numel(loads)
        windConeId = regexp(loads(k).Name, '^WINDCONE_\d+', 'match', 'once');
        if isempty(windConeId)
            regardIndex = regardIndex + 1;
            currentWindCone = '';
        elseif ~strcmp(windConeId, currentWindCone)
            regardIndex = regardIndex + 1;
            currentWindCone = windConeId;
        end

        loads(k).RegardIndex = regardIndex;
        loads(k).ManholeIndex = regardIndex;
        loads(k).Distance_m = loop.rccToFirstRegard_m + ...
                              (regardIndex - 1) * loop.regardSpacing_m;
    end

    if regardIndex ~= loop.equippedRegardCount
        error('Expected %d equipped regards, got %d.', ...
              loop.equippedRegardCount, regardIndex);
    end
end

function modules = localBuildTIModules(loads, ti, f_Hz)
    modules = struct('Name', {}, 'Power_W', {}, 'Pn_fn', {}, 'W1', {}, ...
                     'W2', {}, 'Sat', {}, 'Rm', {}, 'ParameterSource', {}, ...
                     'LeakageSource', {}, 'OpenCircuitVoltageModel_V', {});
    im_vec = ti.saturation.currentVector_A;
    db = ti.database;

    for k = 1:numel(loads)
        power_W = loads(k).TIPower_W;
        idx = find(db.Power_W == power_W, 1);
        if isempty(idx)
            error('Unsupported TI power: %.0f W', power_W);
        end

        L_fuite = db.Leakage_mH(idx) * 1e-3;
        leakageSource = 'validated_linear_interpolation_P45_150';

        V_nom = power_W / 6.6;
        M1 = db.SaturationM1_mH(idx) * 1e-3;
        M2 = db.SaturationM2_mH(idx) * 1e-3;
        i0 = db.SaturationI0_A(idx);
        p_sat = db.SaturationP(idx);
        M_im = (M1 ./ ((1 + (im_vec ./ i0).^p_sat).^(1/p_sat))) + M2;
        lambda_vec = M_im .* im_vec;

        modules(k).Name = loads(k).Name; %#ok<AGROW>
        modules(k).Power_W = power_W;
        modules(k).Pn_fn = [power_W, f_Hz];
        modules(k).W1 = [V_nom, db.WindingResistance_ohm(idx), L_fuite];
        modules(k).W2 = [V_nom, db.WindingResistance_ohm(idx), L_fuite];
        modules(k).Sat = [im_vec, lambda_vec];
        modules(k).Rm = ti.Rm_ohm;
        modules(k).ParameterSource = 'FullLoop_TI_database';
        modules(k).LeakageSource = leakageSource;
        modules(k).OpenCircuitVoltageModel_V = db.OpenCircuitVoltageModel_V(idx);
    end
end
