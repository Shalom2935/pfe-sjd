function FaultSim_runBatch(varargin)
%FAULTSIM_RUNBATCH Run smoke or full fault-simulation batch.
%
% Usage:
%   FaultSim_runBatch('Mode','smoke')
%   FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true)
%   FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true,'MaxScenarios',100)

    parser = inputParser;
    parser.addParameter('Mode', 'smoke', @(s)ischar(s) || isstring(s));
    parser.addParameter('AcceptUnvalidatedRanges', false, @(x)islogical(x) && isscalar(x));
    parser.addParameter('RebuildModel', false, @(x)islogical(x) && isscalar(x));
    parser.addParameter('StartAt', 1, @(x)isnumeric(x) && isscalar(x) && x >= 1);
    parser.addParameter('MaxScenarios', inf, @(x)isnumeric(x) && isscalar(x));
    parser.parse(varargin{:});

    mode = lower(char(parser.Results.Mode));
    cfg = FaultSim_config('Mode', mode, ...
                          'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);

    addpath(cfg.paths.fullLoopDir);
    addpath(cfg.paths.faultSimDir);
    localEnsureDirs(cfg);

    if parser.Results.RebuildModel || ~exist(cfg.model.faultFile, 'file') || ...
            ~exist(fullfile(cfg.paths.metadataDir, 'FaultSim_geometry.mat'), 'file')
        FaultSim_prepareModel('ForceRebuild', true, 'Mode', mode, ...
                              'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);
    else
        FaultSim_prepareModel('ForceRebuild', false, 'Mode', mode, ...
                              'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);
    end

    scenarios = FaultSim_buildScenarioTable('Mode', mode, ...
                                            'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);

    if strcmp(mode, 'smoke') && height(scenarios) > cfg.smoke.maxScenarios
        scenarios = scenarios(1:cfg.smoke.maxScenarios, :);
    end

    if isfinite(parser.Results.MaxScenarios)
        scenarios = scenarios(1:min(height(scenarios), parser.Results.MaxScenarios), :);
    end

    startAt = parser.Results.StartAt;
    if startAt > height(scenarios)
        error('StartAt=%d exceeds scenario count %d.', startAt, height(scenarios));
    end

    geometryFile = fullfile(cfg.paths.metadataDir, 'FaultSim_geometry.mat');
    S = load(geometryFile, 'FullLoop', 'geo', 'FaultSim');
    FullLoop = S.FullLoop;
    geo = S.geo;
    FaultSimBase = S.FaultSim;

    load_system(cfg.model.faultFile);

    featureFile = fullfile(cfg.paths.featureDir, sprintf('FaultSim_features_%s.csv', mode));
    logFile = fullfile(cfg.paths.logDir, sprintf('FaultSim_runlog_%s.csv', mode));

    fprintf('\nFaultSim batch mode: %s\n', mode);
    runCount = height(scenarios) - startAt + 1;
    fprintf('Scenarios selected in table: %d\n', height(scenarios));
    fprintf('Scenarios to run now: %d (rows %d:%d)\n', runCount, startAt, height(scenarios));
    fprintf('Raw output: %s\n', cfg.paths.rawDir);
    fprintf('Features: %s\n', featureFile);
    fprintf('Log: %s\n\n', logFile);

    for rowIdx = startAt:height(scenarios)
        sc = scenarios(rowIdx, :);
        rawFile = fullfile(cfg.paths.rawDir, sprintf('scenario_%06d.mat', sc.scenario_id));

        if exist(rawFile, 'file')
            fprintf('[SKIP] scenario %06d already exists.\n', sc.scenario_id);
            continue;
        end

        tStart = tic;
        try
            fprintf('[RUN ] %06d | %s | %s | d=%.3f m | B=%s\n', ...
                sc.scenario_id, sc.class_name{1}, sc.fault_location_type{1}, ...
                sc.fault_distance_m, sc.brightness_label{1});

            % Refresh DIAM4100 workspace for requested brightness.
            assignin('base', 'FullLoop', FullLoop);
            FullLoop_prepareDIAM4100('ActiveBrightness', sc.brightness_index);
            DIAM4100 = evalin('base', 'DIAM4100');

            FS = localApplyScenarioToFaultState(FaultSimBase, cfg, sc);
            assignin('base', 'FaultSim', FS);
            assignin('base', 'DIAM4100', DIAM4100);

            simIn = Simulink.SimulationInput(cfg.model.faultName);
            simIn = simIn.setVariable('FullLoop', FullLoop);
            simIn = simIn.setVariable('DIAM4100', DIAM4100);
            simIn = simIn.setVariable('FaultSim', FS);
            simIn = simIn.setModelParameter('StopTime', 'FaultSim.simTime_s', ...
                                            'MaxStep', 'FaultSim.Ts_s', ...
                                            'ReturnWorkspaceOutputs', 'on');
            simIn = localApplyLoadBlockParameters(simIn, cfg, FullLoop, sc);

            simOut = sim(simIn);
            raw = localCollectAndResampleSignals(simOut, cfg);
            features = localExtractFeatures(raw, cfg, sc, FS, DIAM4100);

            metadata = table2struct(sc);
            metadata.elapsed_s = toc(tStart);
            metadata.model_file = cfg.model.faultFile;
            metadata.fs_Hz = cfg.fs_Hz;
            metadata.simTime_s = cfg.simTime_s;

            save(rawFile, 'raw', 'features', 'metadata', '-v7.3');
            localAppendTable(struct2table(features), featureFile);
            localAppendLog(logFile, sc, 'OK', '', metadata.elapsed_s);

            fprintf('[ OK ] %06d elapsed %.2f s\n', sc.scenario_id, metadata.elapsed_s);
        catch ME
            elapsed = toc(tStart);
            report = localErrorReport(ME);
            errorFile = localWriteErrorReport(cfg, mode, sc, report);
            message = sprintf('%s | detailed_report=%s', localSingleLine(ME.message), errorFile);
            localAppendLog(logFile, sc, 'ERROR', message, elapsed);
            fprintf(2, '\n[ERROR REPORT] scenario %06d\n%s\n', sc.scenario_id, report);
            warning('[FAIL] scenario %06d failed after %.2f s: %s', sc.scenario_id, elapsed, ME.message);
        end
    end

    fprintf('\n[END] FaultSim batch finished.\n');
end

function localEnsureDirs(cfg)
    dirs = {cfg.paths.outputDir, cfg.paths.rawDir, cfg.paths.featureDir, cfg.paths.metadataDir, cfg.paths.logDir};
    for k = 1:numel(dirs)
        if ~exist(dirs{k}, 'dir')
            mkdir(dirs{k});
        end
    end
end

function FS = localApplyScenarioToFaultState(baseFS, cfg, sc)
    FS = baseFS;
    FS.shuntR_ohm(:) = cfg.inactiveShuntR_ohm;
    FS.shuntC_F(:) = cfg.inactiveShuntC_F;
    FS.seriesR_ohm(:) = cfg.normalSeriesR_ohm;
    FS.activeClassId = sc.class_id;
    FS.activeClassName = sc.class_name{1};
    FS.activeNodeIndex = sc.node_index;
    FS.activeDistance_m = sc.fault_distance_m;

    node = sc.node_index;
    if isnan(node)
        return;
    end

    switch sc.class_name{1}
        case {'HUMIDITY_PROGRESSIVE', 'EARTH_SHORT', 'SURGE_ARRESTER_SHORT', 'TI_INSULATION_LEAKAGE'}
            FS.shuntR_ohm(node) = sc.fault_R_ohm;
        case 'REACTIVE_INCIPIENT'
            FS.shuntC_F(node) = sc.fault_C_F;
        case 'OPEN_CIRCUIT'
            FS.seriesR_ohm(node) = sc.fault_R_ohm;
        case {'HEALTHY', 'TI_LOAD_FAULT'}
            % No primary-loop shunt/series activation here.
        otherwise
            error('Unknown class: %s', sc.class_name{1});
    end
end

function simIn = localApplyLoadBlockParameters(simIn, cfg, FullLoop, sc)
    mdl = cfg.model.faultName;

    % Reset all loads to nominal expression for every scenario.
    for k = 1:numel(FullLoop.loads)
        block = sprintf('%s/LOAD_%03d_%s', mdl, k, FullLoop.loads(k).Name);
        simIn = simIn.setBlockParameter(block, 'Resistance', ...
            sprintf('FullLoop.loads(%d).SecondaryResistance_ohm', k));
    end

    if strcmp(sc.class_name{1}, 'TI_LOAD_FAULT')
        moduleIdx = sc.fault_module_index;
        if isnan(moduleIdx) || moduleIdx < 1 || moduleIdx > numel(FullLoop.loads)
            error('Invalid module index for TI_LOAD_FAULT.');
        end
        block = sprintf('%s/LOAD_%03d_%s', mdl, moduleIdx, FullLoop.loads(moduleIdx).Name);
        switch sc.load_fault_mode{1}
            case 'open'
                simIn = simIn.setBlockParameter(block, 'Resistance', num2str(cfg.loadOpenR_ohm, 16));
            case 'short'
                simIn = simIn.setBlockParameter(block, 'Resistance', num2str(cfg.loadShortR_ohm, 16));
            otherwise
                error('Unsupported load_fault_mode: %s', sc.load_fault_mode{1});
        end
    end
end

function raw = localCollectAndResampleSignals(simOut, cfg)
    names = [cfg.signals.required, cfg.signals.optional];
    available = simOut.who;

    for k = 1:numel(cfg.signals.required)
        if ~ismember(cfg.signals.required{k}, available)
            error('Required signal %s not found in SimulationOutput.', cfg.signals.required{k});
        end
    end

    raw = struct();
    [tU, u] = localTimeseriesToVector(simOut.get('u_RCC'));
    [tI, i] = localTimeseriesToVector(simOut.get('i_RCC'));

    t0 = max([min(tU), min(tI), 0]);
    t1 = min([max(tU), max(tI), cfg.simTime_s]);
    t = (t0:cfg.Ts_s:t1).';
    raw.time_s = t;
    raw.u_RCC_V = interp1(tU, u, t, 'linear', 'extrap');
    raw.i_RCC_A = interp1(tI, i, t, 'linear', 'extrap');

    for k = 1:numel(names)
        name = names{k};
        if ismember(name, {'u_RCC','i_RCC'})
            continue;
        end
        if ismember(name, available)
            try
                [tx, x] = localTimeseriesToVector(simOut.get(name));
                raw.(matlab.lang.makeValidName(name)) = interp1(tx, x, t, 'linear', 'extrap');
            catch
                % Optional debug signals must not kill the simulation.
            end
        end
    end
end

function [t, y] = localTimeseriesToVector(x)
    if isa(x, 'timeseries')
        t = x.Time(:);
        y = squeeze(x.Data);
        y = y(:);
        return;
    end
    if isa(x, 'Simulink.SimulationData.Signal')
        [t, y] = localTimeseriesToVector(x.Values);
        return;
    end
    if isstruct(x) && isfield(x, 'time') && isfield(x, 'signals')
        t = x.time(:);
        y = squeeze(x.signals.values);
        y = y(:);
        return;
    end
    error('Unsupported signal format: %s', class(x));
end

function features = localExtractFeatures(raw, cfg, sc, FS, DIAM4100)
    t = raw.time_s;
    u = raw.u_RCC_V;
    i = raw.i_RCC_A;

    idx = t >= (t(end) - cfg.featureWindow_s);
    tw = t(idx);
    uw = u(idx);
    iw = i(idx);

    features = struct();
    features.scenario_id = sc.scenario_id;
    features.class_id = sc.class_id;
    features.class_name = string(sc.class_name{1});
    features.fault_group = string(sc.fault_group{1});
    features.fault_location_type = string(sc.fault_location_type{1});
    features.fault_distance_m = sc.fault_distance_m;
    features.node_index = sc.node_index;
    features.fault_regard_index = sc.fault_regard_index;
    features.fault_module_index = sc.fault_module_index;
    features.fault_R_ohm = sc.fault_R_ohm;
    features.fault_C_F = sc.fault_C_F;
    features.load_fault_mode = string(sc.load_fault_mode{1});
    features.brightness_index = sc.brightness_index;
    features.brightness_label = string(sc.brightness_label{1});
    features.Iref_Arms = DIAM4100.control.Iref_Arms;

    features.U_RMS = sqrt(mean(uw.^2));
    features.I_RMS = sqrt(mean(iw.^2));
    features.U_peak = max(abs(uw));
    features.I_peak = max(abs(iw));
    features.U_crest = features.U_peak / max(features.U_RMS, eps);
    features.I_crest = features.I_peak / max(features.I_RMS, eps);
    features.U_mean = mean(uw);
    features.I_mean = mean(iw);
    features.U_std = std(uw);
    features.I_std = std(iw);

    specU = localHarmonicSpectrum(tw, uw, cfg.gridFrequency_Hz, cfg.features.harmonics);
    specI = localHarmonicSpectrum(tw, iw, cfg.gridFrequency_Hz, cfg.features.harmonics);

    for h = cfg.features.harmonics
        key = sprintf('H%d', h);
        features.(['U_' key '_amp']) = specU.amp(h);
        features.(['U_' key '_phase']) = specU.phase(h);
        features.(['I_' key '_amp']) = specI.amp(h);
        features.(['I_' key '_phase']) = specI.phase(h);

        z = specU.complex(h) / max(specI.complex(h), eps);
        features.(['Z_' key '_abs']) = abs(z);
        features.(['Z_' key '_angle']) = angle(z);
    end

    hList = cfg.features.harmonics;
    hNoFund = hList(hList ~= 1);
    features.THD_U = sqrt(sum(arrayfun(@(h)specU.amp(h).^2, hNoFund))) / max(specU.amp(1), eps);
    features.THD_I = sqrt(sum(arrayfun(@(h)specI.amp(h).^2, hNoFund))) / max(specI.amp(1), eps);
end

function spec = localHarmonicSpectrum(t, x, f0, harmonics)
    x = x(:);
    t = t(:);
    fs = 1 / median(diff(t));
    n = numel(x);
    if n < 8
        error('Not enough samples for FFT.');
    end

    x = x - mean(x);
    w = 0.5 - 0.5*cos(2*pi*(0:n-1)'/(n-1));
    X = fft(x .* w);
    scale = sum(w);

    spec.amp = containers.Map('KeyType','double','ValueType','double');
    spec.phase = containers.Map('KeyType','double','ValueType','double');
    spec.complex = containers.Map('KeyType','double','ValueType','any');

    for h = harmonics
        f = h * f0;
        idx = round(f / fs * n) + 1;
        idx = max(1, min(idx, n));
        value = 2 * X(idx) / scale;
        spec.amp(h) = abs(value);
        spec.phase(h) = angle(value);
        spec.complex(h) = value;
    end
end

function filePath = localWriteErrorReport(cfg, mode, sc, report)
    if ~exist(cfg.paths.logDir, 'dir')
        mkdir(cfg.paths.logDir);
    end
    filePath = fullfile(cfg.paths.logDir, ...
        sprintf('FaultSim_error_%s_%06d.txt', mode, sc.scenario_id));
    fid = fopen(filePath, 'w');
    if fid < 0
        error('Cannot write error report: %s', filePath);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', report);
end

function text = localSingleLine(text)
    text = regexprep(char(text), '\s+', ' ');
end

function report = localErrorReport(ME)
    try
        report = getReport(ME, 'extended', 'hyperlinks', 'off');
    catch
        report = ME.message;
    end

    if ~isempty(ME.cause)
        causeReports = strings(1, numel(ME.cause));
        for k = 1:numel(ME.cause)
            causeReports(k) = sprintf('Cause %d:\n%s', k, localErrorReport(ME.cause{k}));
        end
        report = sprintf('%s\n\n%s', report, strjoin(causeReports, newline));
    end
end

function localAppendTable(T, filePath)
    if exist(filePath, 'file')
        writetable(T, filePath, 'WriteMode', 'append', 'WriteVariableNames', false);
    else
        writetable(T, filePath);
    end
end

function localAppendLog(logFile, sc, status, message, elapsed_s)
    row = table(sc.scenario_id, string(sc.class_name{1}), string(sc.fault_location_type{1}), ...
        sc.fault_distance_m, sc.brightness_index, string(status), string(message), elapsed_s, ...
        'VariableNames', {'scenario_id','class_name','fault_location_type','fault_distance_m', ...
                          'brightness_index','status','message','elapsed_s'});
    localAppendTable(row, logFile);
end
