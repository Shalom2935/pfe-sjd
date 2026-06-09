function bestSchedule = DIAM4100_tuneKiSweep(varargin)
%DIAM4100_TUNEKISWEEP Brute-force Ki tuning by effective load and brightness.
%
% This is the scientific tuning pass: for each load ratio and each brightness
% level, the model is simulated for a grid of Ki values. The selected Ki is
% the lowest-cost value satisfying the validation constraints. If no value
% passes, the least-bad value is still reported and marked as failing.
%
% Usage:
%   bestSchedule = DIAM4100_tuneKiSweep;
%   bestSchedule = DIAM4100_tuneKiSweep('KiCandidates', 40:10:320);

    opts = localParseInputs(varargin{:});
    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);

    run(fullfile(thisDir, 'DIAM4100_simParams.m'));
    baseParams = evalin('base', 'DIAM4100');

    if ~exist(opts.OutputDir, 'dir')
        mkdir(opts.OutputDir);
    end

    rows = {};
    model = baseParams.model.name;

    for loadRatio = opts.LoadRatios
        for b = opts.BrightnessIndices
            for Ki = opts.KiCandidates
                DIAM4100_user = struct();
                DIAM4100_user.loadTap.eighths = baseParams.loadTap.eighths;
                DIAM4100_user.load.effectivePower_VA = ...
                    baseParams.load.ledNominalPower_VA * loadRatio;
                DIAM4100_user.control.activeBrightness = b;
                assignin('base', 'DIAM4100_user', DIAM4100_user);

                run(fullfile(thisDir, 'DIAM4100_simParams.m'));
                DIAM4100 = evalin('base', 'DIAM4100');
                DIAM4100.control.Ki = Ki;
                assignin('base', 'DIAM4100', DIAM4100);
                DIAM4100_applyModelParameters('SaveModel', opts.SaveModel, 'Instrument', true);

                try
                    simOut = sim(model, ...
                        'StopTime', num2str(DIAM4100.validation.simTime_s), ...
                        'ReturnWorkspaceOutputs', 'on');
                    Irms = simOut.get('DIAM4100_Irms');
                    metrics = DIAM4100_measureResponse(Irms.Time, ...
                                                       squeeze(Irms.Data), ...
                                                       DIAM4100.control.Iref_Arms, ...
                                                       DIAM4100.norms);
                    err = "";
                catch ME
                    metrics = localEmptyMetrics(DIAM4100.control.Iref_Arms);
                    err = string(ME.message);
                end

                score = localScore(metrics, DIAM4100);
                rows(end+1, :) = { ...
                    DIAM4100.loadTap.eighths, ...
                    DIAM4100.load.nominalRatio, ...
                    DIAM4100.load.effectivePower_VA, ...
                    DIAM4100.load.R_ohm, ...
                    string(DIAM4100.control.activeBrightnessLabel), ...
                    DIAM4100.control.Iref_Arms, ...
                    Ki, ...
                    metrics.peak_Arms, ...
                    metrics.overshoot_A, ...
                    metrics.overshoot_pct, ...
                    metrics.final_Arms, ...
                    metrics.finalError_A, ...
                    metrics.settlingTime_s, ...
                    metrics.maxContinuous120Duration_s, ...
                    metrics.meetsFAASettling, ...
                    metrics.meetsIECSettling, ...
                    ~metrics.exceedsFAA120Duration, ...
                    ~metrics.exceedsIECStepLimit, ...
                    metrics.pass, ...
                    score, ...
                    err};
            end
        end
    end

    sweep = cell2table(rows, 'VariableNames', { ...
        'LoadTap_eighths', ...
        'LoadRatio', ...
        'LoadPower_VA', ...
        'LoadResistance_ohm', ...
        'Brightness', ...
        'Iref_Arms', ...
        'Ki', ...
        'Peak_Arms', ...
        'Overshoot_A', ...
        'Overshoot_pct', ...
        'Final_Arms', ...
        'FinalError_A', ...
        'SettlingTime_s', ...
        'MaxContinuous120Duration_s', ...
        'MeetsFAASettling', ...
        'MeetsIECSettling', ...
        'MeetsFAATransient120Duration', ...
        'MeetsIECStepSurgeLimit', ...
        'Pass', ...
        'Score', ...
        'Error'});

    sweepCsv = fullfile(opts.OutputDir, 'DIAM4100_Ki_sweep_results.csv');
    writetable(sweep, sweepCsv);

    bestSchedule = localSelectBest(sweep);
    bestCsv = fullfile(opts.OutputDir, 'DIAM4100_Ki_best_schedule.csv');
    writetable(bestSchedule, bestCsv);

    assignin('base', 'DIAM4100_Ki_sweep_results', sweep);
    assignin('base', 'DIAM4100_Ki_best_schedule', bestSchedule);
    evalin('base', 'clear DIAM4100_user');

    DIAM4100_plotKiSweep('SweepCsv', sweepCsv, 'BestCsv', bestCsv, 'OutputDir', opts.OutputDir);
end

function opts = localParseInputs(varargin)
    parser = inputParser;
    parser.addParameter('LoadRatios', [0.20 0.35 0.50 0.75 1.00], ...
        @(x) isnumeric(x) && all(x > 0));
    parser.addParameter('BrightnessIndices', 1:6, @(x) isnumeric(x) && all(x >= 1));
    parser.addParameter('KiCandidates', 40:10:320, @(x) isnumeric(x) && all(x > 0));
    parser.addParameter('SaveModel', false, @(x) islogical(x) || isnumeric(x));
    parser.addParameter('OutputDir', fullfile(fileparts(mfilename('fullpath')), 'figures'), ...
        @(x) ischar(x) || isstring(x));
    parser.parse(varargin{:});
    opts = parser.Results;
    opts.OutputDir = char(opts.OutputDir);
end

function score = localScore(metrics, DIAM4100)
    tolerance_A = DIAM4100.norms.FAA.currentTolerance_A;
    settling = metrics.settlingTime_s;
    if isnan(settling)
        settling = 10 * DIAM4100.norms.FAA.controlSettlingTime_s;
    end

    score = 20 * max(0, abs(metrics.finalError_A) / tolerance_A - 1) + ...
            5 * max(0, metrics.overshoot_A / tolerance_A - 1) + ...
            settling / DIAM4100.norms.FAA.controlSettlingTime_s + ...
            0.02 * metrics.overshoot_pct;

    if ~metrics.pass
        score = score + 100;
    end
end

function best = localSelectBest(sweep)
    keys = unique(sweep(:, {'LoadRatio', 'Brightness'}), 'rows');
    bestRows = table();
    for k = 1:height(keys)
        idx = sweep.LoadRatio == keys.LoadRatio(k) & ...
              string(sweep.Brightness) == string(keys.Brightness(k));
        group = sweep(idx, :);
        passRows = group(group.Pass == 1, :);
        if ~isempty(passRows)
            [~, bestIdx] = min(passRows.Score);
            bestRows = [bestRows; passRows(bestIdx, :)]; %#ok<AGROW>
        else
            [~, bestIdx] = min(group.Score);
            bestRows = [bestRows; group(bestIdx, :)]; %#ok<AGROW>
        end
    end
    best = bestRows;
end

function metrics = localEmptyMetrics(ref_Arms)
    metrics = struct();
    metrics.reference_Arms = ref_Arms;
    metrics.peak_Arms = NaN;
    metrics.final_Arms = NaN;
    metrics.finalError_A = NaN;
    metrics.overshoot_A = NaN;
    metrics.overshoot_pct = NaN;
    metrics.settlingTime_s = NaN;
    metrics.maxContinuous120Duration_s = NaN;
    metrics.exceedsIECStepLimit = true;
    metrics.exceedsFAA120Duration = true;
    metrics.meetsFAASettling = false;
    metrics.meetsIECSettling = false;
    metrics.pass = false;
end
