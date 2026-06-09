function FullLoop_smokeTest()
%FULLLOOP_SMOKETEST Check parameter loading and Ki scheduling.

    thisDir = fileparts(mfilename('fullpath'));
    cd(thisDir);
    run(fullfile(thisDir, 'FullLoop_simParams.m'));
    FullLoop_prepareDIAM4100('ActiveBrightness', 6);

    FullLoop = evalin('base', 'FullLoop');
    DIAM4100 = evalin('base', 'DIAM4100');

    fid = fopen(fullfile(thisDir, 'FullLoop_smokeTest.log'), 'w');
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, 'loads=%d\n', numel(FullLoop.loads));
    fprintf(fid, 'secondaryVA=%.3f\n', FullLoop.summary.totalSecondaryPower_VA);
    fprintf(fid, 'tiW=%.3f\n', FullLoop.summary.totalTIPower_W);
    fprintf(fid, 'segments=%d\n', FullLoop.segments.count);
    fprintf(fid, 'length=%.3f\n', sum(FullLoop.segments.length_m));
    fprintf(fid, 'brightness=%s\n', DIAM4100.control.activeBrightnessLabel);
    fprintf(fid, 'Iref=%.3f\n', DIAM4100.control.Iref_Arms);
    fprintf(fid, 'Ki=%.6f\n', DIAM4100.control.Ki);
    fprintf(fid, 'loadRatio=%.6f\n', DIAM4100.control.kiScheduleLoadRatio);
end
