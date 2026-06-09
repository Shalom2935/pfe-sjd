function FullLoop_openModel(activeBrightness)
%FULLLOOP_OPENMODEL Initialize workspace and open the generated full-loop model.
%
% Usage from MATLAB:
%   cd('...\model\FullLoop_DIAM4100')
%   FullLoop_openModel          % default B5
%   FullLoop_openModel(4)       % B3, because B0=1 ... B5=6

    if nargin < 1
        activeBrightness = 6;
    end

    thisDir = fileparts(mfilename('fullpath'));
    cd(thisDir);
    run(fullfile(thisDir, 'FullLoop_simParams.m'));

    FullLoop = evalin('base', 'FullLoop');
    FullLoop.diam4100.activeBrightness = activeBrightness;
    assignin('base', 'FullLoop', FullLoop);

    FullLoop_prepareDIAM4100('ActiveBrightness', activeBrightness);

    modelFile = fullfile(thisDir, [FullLoop.model.name '.slx']);
    load_system(modelFile);
    open_system(FullLoop.model.name);
    fprintf('Opened %s with brightness index %d.\n', FullLoop.model.name, activeBrightness);
end
