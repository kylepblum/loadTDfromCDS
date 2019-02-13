function trial_data = loadTDfromCDS(filename,params)
    % loadtdfromcds Loads trial_data structure from CDS file
    %   trial_data = loadtdfromcds(filename,params)
    %   Inputs:
    %       filename - (string) location and name of CDS file to load
    %       params - (struct) indicating which signals to load into trial_data
    %           array_name - (string or cell array of strings) name of
    %               array, e.g. 'S1' or {'S1','cuneate'}
    %           cont_signal_names - (cell array of strings) list of signal names to extract.
    %               Could be one of:
    %                   'pos'
    %                   'vel'
    %                   'acc'
    %                   'force'
    %                   'motor_control'
    %                   'markers'
    %                   'joint_ang'
    %                   'joint_vel'
    %                   'muscle_len'
    %                   'muscle_vel'
    %                   'opensim_hand_pos'
    %                   'opensim_hand_vel'
    %                   'opensim_hand_acc'
    %                   'opensim_elbow_pos'
    %                   'opensim_elbow_vel'
    %                   'opensim_elbow_acc'
    %               List needs to be in row vector form (default: {})
    %           extract_emg - (bool) whether or not to extract emg signals (default: false)
    %           event_names - (cell array of string) list of event names to extract.
    %               Only supports events that end in 'Time' (default: {'startTime','endTime'})
    %           bin_size - (numeric) bin size at which to load trial_data (default: 0.01)
    %           trial_meta - (cell array of strings) meta information about each trial (like target_direction)
    %               to be loaded in from CDS trial table (names should be desired column names of trial table)
    %           meta - (struct) meta information for given file to be put into loaded trial data, like epoch name
    %               Note: most typical meta information (e.g. monkey, date, task) are automatically extracted from
    %               the CDS, so you don't need to add them here.

    %% default variables
    cont_signal_names = {};
    extract_emg = false;
    event_names = {'startTime','endTime'};
    bin_size = 0.01;
    trial_meta = {};
    meta = [];
    array_name = '';
    cds_array_name = '';

    assignParams(who,params)

    % check filename
    assert(ischar(filename),'filename must be a string')

    %% parameter integrity checks
    assert(iscell(cont_signal_names),'cont_signal_names needs to be a cell array')
    assert(islogical(extract_emg),'extract_emg needs to be a bool')
    assert(iscell(event_names),'event_names needs to be a cell array')
    assert(isnumeric(bin_size),'bin_size needs to be a number')
    assert(iscell(trial_meta),'trial_meta needs to be a cell')
    assert(isempty(meta) || isstruct(meta),'meta needs to be a struct')
    assert(~isempty(array_name), 'array_name is missing')
    if isempty(cds_array_name)
        warning('CDS array name not provided')
    end
    
    if ~iscell(array_name)
        array_name = {array_name};
    end
    assert(ischar(array_name{1}),'array_name must contain a string')
    
    if ~isempty(cds_array_name)
        if ~iscell(cds_array_name) && ~isempty(cds_array_name)
            cds_array_name = {cds_array_name};
        end
        assert(ischar(cds_array_name{1}),'cds_array_name must contain a string')
        
        assert(length(array_name)==length(cds_array_name),'Length of array_name must match length of cds_array_name (if provided)')
    else
        cds_array_name = repmat({''},size(array_name));
    end
    
    
    %% Make TD
    cont_signal_labels = get_signal_labels(cont_signal_names);
    spike_routine = @processCDSspikes;
    cds_routine = @processCDS;
    
    if extract_emg
        emg_signal_names = get_emg_names();
    else
        emg_signal_names = {};
    end
    
    % trial_data loading parameters...
    if ~isempty(meta)
        td_params = struct('bin_size',bin_size,'meta',meta);
    else
        td_params = struct('bin_size',bin_size);
    end
    
    %% load it in
    % get signal info
    signal_info = cell(1,length(array_name)+1);
    for arraynum = 1:length(array_name)
        signal_info{arraynum} = initSignalStruct( ...
            'filename',filename, ...
            'routine',spike_routine, ...
            'params',struct('cds_array_name',cds_array_name{arraynum}), ... 
            'name',array_name{arraynum}, ... % it gets stored under this name... in case of spikes, this gives S1_spikes
            'type','spikes', ... % which type... see documentation of initSignalStruct
            'label','');
    end
    
    signal_info{end} = initSignalStruct( ... % continuous data
            'filename',filename, ...
            'routine',cds_routine, ...
            'params',struct('trial_meta',{trial_meta}), ...
            'name',[...
                cont_signal_names,...
                emg_signal_names,...
                event_names,...
                ], ... % stored in this name, matched to the labels below which correspond to the output of the processing routine
            'type',[...
                repmat({'generic'},1,length(cont_signal_names)),...
                repmat({'emg'},1,length(emg_signal_names)),...
                repmat({'event'},1,length(event_names)),...
                ],...
            'label',[...
                cont_signal_labels,...
                strcat('EMG_',emg_signal_names),...
                event_names,...
                ], ... % can also pass [1 2],[3 4] etc if you know the arrangment of the signals in the data struct
            'operation',[]);
    
    % load trial_data (will result in warning for no meta info, but we're
    % taking most meta info from the CDS anyway)
    trial_data = convertDataToTD(signal_info,td_params);
    
    % add some meta information
    if any(strcmpi(cont_signal_names,'markers'))
        trial_data.marker_names = sort(get_marker_labels());
    end
    if any(contains(cont_signal_names,'joint'))
        trial_data.joint_names = get_joint_labels();
    end
    if any(contains(cont_signal_names,'muscle'))
        trial_data.muscle_names = get_muscle_labels();
    end
    if any(strcmpi(cont_signal_names,'motor_control'))
        trial_data.motorcontrol_names = {'MotorControlSho','MotorControlElb'};
    end
    
    % make it pretty
    trial_data = reorderTDfields(trial_data);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Subfunctions %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function labels = get_signal_labels(signal_names)
    % returns labels given a list of signal names
    labels = cell(1,length(signal_names));
    for sig_idx = 1:length(signal_names)
        switch lower(signal_names{sig_idx})
            case 'pos'
                labels{sig_idx} = {'x','y'};
            case 'vel'
                labels{sig_idx} = {'vx','vy'};
            case 'acc'
                labels{sig_idx} = {'ax','ay'};
            case 'force'
                labels{sig_idx} = {'fx','fy','fz','mx','my','mz'};
            case 'motor_control'
                labels{sig_idx} = {'MotorControlSho','MotorControlElb'};
            case 'markers'
                labels{sig_idx} = sort(get_marker_labels());
            case 'joint_ang'
                labels{sig_idx} = strcat(get_joint_labels(),'_ang');
            case 'joint_vel'
                labels{sig_idx} = strcat(get_joint_labels(),'_vel');
            case 'muscle_len'
                labels{sig_idx} = strcat(get_muscle_labels(),'_len');
            case 'muscle_vel'
                labels{sig_idx} = strcat(get_muscle_labels(),'_muscVel');
            case 'opensim_hand_pos'
                labels{sig_idx} = strcat({'X','Y','Z'},{'_handPos'});
            case 'opensim_hand_vel'
                labels{sig_idx} = strcat({'X','Y','Z'},{'_handVel'});
            case 'opensim_hand_acc'
                labels{sig_idx} = strcat({'X','Y','Z'},{'_handAcc'});
            case 'opensim_elbow_pos'
                labels{sig_idx} = strcat({'X','Y','Z'},{'_elbowPos'});
            case 'opensim_elbow_vel'
                labels{sig_idx} = strcat({'X','Y','Z'},{'_elbowVel'});
            case 'opensim_elbow_acc'
                labels{sig_idx} = strcat({'X','Y','Z'},{'_elbowAcc'});
        end
    end
end

function names = get_emg_names()
    % function to return the names of EMGs
    
    names = {...
        'BiMed',...
        'FCR',...
        'FCU',...
        'FDS',...
        'DeltAnt',...
        'DeltMid',...
        'DeltPos',...
        'Trap',...
        'Lat',...
        'TerMaj',...
        'InfSpin',...
        'TriMid',...
        'TriLat',...
        'TriMed',...
        'Brad',...
        'ECRb',...
        'ECU',...
        'EDC',...
        'PecSup',...
        'PecInf',...
        'Brach',...
        'BiLat',...
        };
end

function names = get_joint_labels()
    % function to return the names of joints
    
    names = {...
        'shoulder_adduction',...
        'shoulder_rotation',...
        'shoulder_flexion',...
        'elbow_flexion',...
        'radial_pronation',...
        'wrist_flexion',...
        'wrist_abduction',...
        };
end

function names = get_marker_labels()
    % function to return the names of markers, as they appear in raw cds format
    
    temp = {...
        'Marker_1',...
        'Marker_2',...
        'Marker_3',...
        'Marker_4',...
        'Marker_5',...
        'Marker_6',...
        'Marker_7',...
        'Marker_8',...
        'Shoulder_JC',...
        'Pronation_Pt1',...
        };
    names = cell(1,3*length(temp));
    
    for i = 1:length(temp)
        names(((i-1)*3+1):(i*3)) = strcat(temp(i),{'_y','_z','_x'});
    end
end

function names = get_muscle_labels()
    % function to return the names of muscles
    
    names = {...
        'abd_poll_longus',...
        'anconeus',...
        'bicep_lh',...
        'bicep_sh',...
        'brachialis',...
        'brachioradialis',...
        'coracobrachialis',...
        'deltoid_ant',...
        'deltoid_med',...
        'deltoid_pos',...
        'dorsoepitrochlearis',...
        'ext_carpi_rad_longus',...
        'ext_carp_rad_brevis',...
        'ext_carpi_ulnaris',...
        'ext_digitorum',...
        'ext_digiti',...
        'ext_indicis',...
        'flex_carpi_radialis',...
        'flex_carpi_ulnaris',...
        'flex_digit_profundus',...
        'flex_digit_superficialis',...
        'flex_poll_longus',...
        'infraspinatus',...
        'lat_dorsi_sup',...
        'lat_dorsi_cen',...
        'lat_dorsi_inf',...
        'palmaris_longus',...
        'pectoralis_sup',...
        'pectoralis_inf',...
        'pronator_quad',...
        'pronator_teres',...
        'subscapularis',...
        'supinator',...
        'supraspinatus',...
        'teres_major',...
        'teres_minor',...
        'tricep_lat',...
        'tricep_lon',...
        'tricep_sho',...
        };
end
