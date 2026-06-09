function DIAM4100 = FullLoop_prepareDIAM4100(varargin)
%FULLLOOP_PREPAREDIAM4100 Build the DIAM4100 workspace structure for full-loop runs.
%
% The detailed DIAM4100 blocks still reference the DIAM4100 structure. This
% initializer therefore reuses the existing DIAM4100_simParams.m script, then
% overrides Ki with the schedule obtained from the Ki sweep CSV.

    opts = localParseInputs(varargin{:});
    thisDir = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(fileparts(thisDir));
    diamDir = fullfile(projectRoot, 'model', 'DIAM4100');

    if evalin('base', 'exist(''FullLoop'', ''var'')') ~= 1
        run(fullfile(thisDir, 'FullLoop_simParams.m'));
    end
    FullLoop = evalin('base', 'FullLoop');

    DIAM4100_user = struct();
    DIAM4100_user.loadTap.eighths = 4;
    DIAM4100_user.load.effectivePower_VA = FullLoop.summary.totalSecondaryPower_VA;
    DIAM4100_user.control.activeBrightness = opts.ActiveBrightness;
    assignin('base', 'DIAM4100_user', DIAM4100_user);

    run(fullfile(diamDir, 'DIAM4100_simParams.m'));
    DIAM4100 = evalin('base', 'DIAM4100');

    label = DIAM4100.control.activeBrightnessLabel;
    loadRatio = FullLoop.summary.totalSecondaryPower_VA / ...
                FullLoop.diam4100.referenceLoadPower_VA;
    [Ki, scheduleInfo] = FullLoop_lookupKiFromSweep( ...
        FullLoop.diam4100.kiScheduleCsv, label, loadRatio);

    DIAM4100.control.Ki = Ki;
    DIAM4100.control.kiScheduleSource = 'DIAM4100_Ki_best_schedule.csv';
    DIAM4100.control.kiScheduleLoadRatio = loadRatio;
    DIAM4100.control.kiScheduleInfo = scheduleInfo;
    DIAM4100.validation.simTime_s = FullLoop.validation.simTime_s;

    assignin('base', 'DIAM4100', DIAM4100);
    evalin('base', 'clear DIAM4100_user');

    fprintf('Full-loop DIAM4100: %s, Iref=%.3f A, loadRatio=%.3f, Ki=%.3f\n', ...
        label, DIAM4100.control.Iref_Arms, loadRatio, Ki);
end

function opts = localParseInputs(varargin)
    parser = inputParser;
    parser.addParameter('ActiveBrightness', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
    parser.parse(varargin{:});
    opts = parser.Results;

    if isempty(opts.ActiveBrightness)
        if evalin('base', 'exist(''FullLoop'', ''var'')') == 1
            FullLoop = evalin('base', 'FullLoop');
            opts.ActiveBrightness = FullLoop.diam4100.activeBrightness;
        else
            opts.ActiveBrightness = 6;
        end
    end
end
