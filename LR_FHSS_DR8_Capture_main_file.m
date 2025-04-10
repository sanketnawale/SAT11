clear all; close all; clc;
diary('text7.txt');  % Start saving all console output to text4.txt
diary on;

%% 🌍 Simulation Parameters
tic
Simulation_T = 110 * 60;  % Total simulation time (110 minutes in seconds)
Time_Step = 60;           % Time step (1 min = 60 sec)
MonteCarlo = 5000;        % Monte Carlo simulation (number of packets per node)
Nodes = 4;                % Number of ground nodes (Rome, Milan, NodeRM)
Pkct_Per_Hour = 10;      % Packets per hour for each node

%% 🌍 Ground Nodes (Rome, Milan, NodeRM)
Node_Coordinates = [ 
    41.9028, 12.4964;  
    45.4642, 9.1900; 
    45.4408, 12.3155; 
    41.9, 12.5         
];

%% 🛰️ Satellite Constellation (Walker)
Sat_Per_Plane = 648;
Num_Planes = 18;
Total_Sats = Sat_Per_Plane * Num_Planes;
Orbital_Inclination = deg2rad(87);
H = 12000e3;
Earth_Radius = 6378e3;
Time_Vector = 0:Time_Step:Simulation_T;

% 🛰️ Generate Walker Delta Constellation
oev = walker_delta(Sat_Per_Plane, Num_Planes, 1, pi, Earth_Radius + H, Orbital_Inclination);
Num_Satellites = size(oev, 1);
num_steps = length(Time_Vector);

%% 📡 Obtain Satellite Geometry
[Distances, Elevation_Angles, Ground_Distances, Visibility, Num_Visible_Sats, Sat_IDs, Latitudes, Longitudes,Sat_To_NodeRM_Delay] = ...
    Satellite_Geometry(H, Node_Coordinates, oev, Earth_Radius, Time_Vector);
Visible_Sat_Matrix = zeros(length(Time_Vector), 4);

%% Additional storage for packet reception times info
% (For Rome and Milan, we build a string for each time step indicating
% the packet arrival (reception) times per visible satellite.
% For NodeRM, we store a simple message.)
Rome_PktReception = cell(length(Time_Vector), 1);
Milan_PktReception = cell(length(Time_Vector), 1);
NodeRM_PktReception = cell(length(Time_Vector), 1);
% Initialize global Packet ID counter
PacketIDCounter = 0; % This will generate unique IDs for all packets
%% 🌍 LoRa Duty Cycle (Sleep Mode)
Duty_Cycle_Percentage = 1; % Example: Node transmits only 1% of the time
LoRa_Sleep_Time = (100 / Duty_Cycle_Percentage - 1) * 60; % Convert to seconds



%% 🌍 LR-FHSS Communication Parameters
Payload = 10;            
Header_N_DR8 = 3;        
Code_Rate = 1/3;         
Header_duration = 0.233; 
F_duration = 0.05;       
Header_ToA_DR8 = Header_N_DR8 * Header_duration;

% Time on Air Calculation
[ToA_DR8, ToA_DR8_WH] = ToA_Packets_DR8(Payload, Header_ToA_DR8, 2);
ToA_DR8(1) = ToA_DR8(1) + (6.472 / 1000);

% Fragmentation Details
fragment_duration = 50 / 1000;
fragment_50_ms = floor(ToA_DR8_WH(1) / fragment_duration);
Last_fragment_duration = ((ToA_DR8_WH(1) / fragment_duration) - fragment_50_ms) * fragment_duration;
fragment_PHY_length = fragment_50_ms + 1;
fragment_length = Header_N_DR8 + 1 + fragment_PHY_length;

% Define Monte Carlo Simulations
OBW_channels = 280;
Collision_Threshold = 2 * 50e-3;

% 🚀 Define Link Budget Parameters
Tx_Power = 14;  
Antenna_Gain = 2;  
Noise_Floor = -174 + 10 * log10(137e6);  

%% 📊 Initialize Matrices
SuccessRate = zeros(Nodes, length(Time_Vector));
Collisions = zeros(Nodes, length(Time_Vector));
Received_Packets_NodeRM = zeros(1, length(Time_Vector));
Signal_Delay = zeros(Nodes, Num_Satellites, num_steps);


Duty_Cycle = 5;  % 10% duty cycle (adjustable)
sleep_time = (1 - Duty_Cycle) * 60;  % Convert to seconds
wakeup_time = Duty_Cycle * 60;  % Convert to seconds
%% Retransmission Setup
%% Retransmission Setup
%retransmissionQueue = cell(Nodes-1, 1);
retransmissionQueue = cell(1, 1);  % Only for Node 2

for node = 1:Nodes-1
    retransmissionQueue{node} = [];  % [PacketID, attempts, nextTxTime, originating_node]
end
maxRetransmissions = 3;
retransmissionDelay = 60;

Rome_RX_Count = 0;
Milan_RX_Count = 0;
Rome_ACK_Count = 0;
Rome_NACK_Count = 0;
Milan_ACK_Count = 0;
Milan_NACK_Count = 0;
Total_ACKs=0;
TotalPacketsReceived=0;
TotalPacketsReceived = 0;
TotalCollidedPackets = 0;
Loss_MissingHeaders = 0;
Loss_InsufficientFragments = 0;
Loss_LowSNR = 0;
Loss_Other = 0;  % fallback for anything unexpected
Loss_NoCommonSatellite = 0;
TotalIgnoredNodeRM = 0;  % To count total duplicate packet copies ignored at NodeRM
TotalTxPacketsRome = 0;
TotalTxPacketsMilan = 0;
RawPacketArrivalCounter = 0;
TotalCollisions = 0;  % Total collided packets across all satellites
AllSeenPacketIDs=0;
Venice_RX_Count = 0;
Venice_ACK_Count = 0;
Venice_NACK_Count = 0;
TotalTxPacketsVenice = 0;
Venice_PktReception = cell(length(Time_Vector), 1);









% ✅ Move this here!
ACKedPackets = containers.Map('KeyType','double','ValueType','logical');
NodeRM_PacketHistory = containers.Map('KeyType', 'double', 'ValueType', 'double');
CumulativeACKedPackets = containers.Map('KeyType','double','ValueType','logical');

NACKedPackets = containers.Map('KeyType','double','ValueType','logical');
CumulativeACKedPackets = containers.Map('KeyType','double','ValueType','logical');

    RetransmittedPackets = containers.Map('KeyType','double','ValueType','logical');

Retrans_ACKed = containers.Map('KeyType', 'double', 'ValueType', 'logical');
Retrans_ACKed = containers.Map('KeyType', 'double', 'ValueType', 'logical');
Retrans_ACKed = containers.Map('KeyType', 'double', 'ValueType', 'logical');


%% 📡 Main Simulation Loop
for t = 1:length(Time_Vector)
    current_time_sec = Time_Vector(t);
    current_time_min = current_time_sec / 60;
    fprintf('\n⏳ Time %.2f min: \n', current_time_min);
    Visible_Sat_Matrix(t, :) = [current_time_min, Num_Visible_Sats(1, t), Num_Visible_Sats(2, t), Num_Visible_Sats(3, t)];
    NodeRM_Packet_Times = [];

    for n = 1:Nodes-1
        if Num_Visible_Sats(n, t) == 0
            fprintf('🚫 Node %d has no visible satellites at %.2f min\n', n, current_time_min);
            continue;
        end


       % relative_time = mod(current_time_min, 2);
        relative_time = mod(current_time_min, 2); % Alternates every 1 minute (cycle: 1 minute awake + 1 minute asleep)

        if relative_time >= 1
    % Node is sleeping during the second minute of the cycle
            fprintf('💤 Node %d is sleeping at %.2f min\n', n, current_time_min);
            continue; % Skip packet transmission for sleeping nodes
        else
    % Node is awake during the first minute of the cycle
            fprintf('🔋 Node %d is awake at %.2f min\n', n, current_time_min);
        end


            Visible_Sats = Sat_IDs{n, t};
            Sat_Receive_Times = cell(Total_Sats, 1);
            Retrans_Sat_Receive_Times = cell(Total_Sats, 1);



        % 🔁 Retransmissions
        % 🔁 Retransmissions
        if ~isempty(retransmissionQueue{n})
    dueIdx = find(retransmissionQueue{n}(:,3) <= current_time_sec);
    for k = 1:numel(dueIdx)
        packet_id = retransmissionQueue{n}(dueIdx(k), 1);
        attempt_num = retransmissionQueue{n}(dueIdx(k), 2) + 1;

        % Only retransmit if not already ACKed
        if isKey(ACKedPackets, packet_id)
            continue;
        end

        % Schedule arrival times for retransmission
        for chosen_sat = Visible_Sats
            arrival_time = current_time_sec + Signal_Delay(n, chosen_sat, t);
            Retrans_Sat_Receive_Times{chosen_sat} = ...
                [Retrans_Sat_Receive_Times{chosen_sat}; packet_id, arrival_time];
        end

        fprintf('🔁 Node %d Retransmitting Packet ID %d (Attempt %d)\n', ...
            n, packet_id, attempt_num);
    end
end

        

        % 🚀 Proceed with Packet Transmission Logic for Awake Nodes
        Num_Packets = 30;
        lambda = 1 / (60 / Pkct_Per_Hour); % Packet inter-arrival time parameter
        Inter_Arrival_Times = exprnd(1/lambda, 1, Num_Packets); % Generate random inter-arrival times
        Tx_Timestamps = cumsum(Inter_Arrival_Times); % Generate timestamps
        Tx_Timestamps(Tx_Timestamps > wakeup_time) = []; % Exclude transmissions outside wake time

        Visible_Sats = Sat_IDs{n, t}; % Retrieve visible satellites for the node
        Sat_Receive_Times = cell(Total_Sats, 1); % Initialize satellite receive times

        

        % Packet Transmission Logic for Rome and Milan Nodes
        for pkt = 1:length(Tx_Timestamps)
            % Increment Packet ID Counter
            PacketIDCounter = PacketIDCounter + 1;
            UniquePktID = PacketIDCounter; % Assign a unique packet ID

            for chosen_sat = Visible_Sats
            arrival_time = Tx_Timestamps(pkt) + Signal_Delay(n, chosen_sat, t);
                if ~isKey(ACKedPackets, UniquePktID)
                    Sat_Receive_Times{chosen_sat} = [Sat_Receive_Times{chosen_sat}; UniquePktID, arrival_time];
                end
            end
                % Log the packet transmission (optional, for debugging)
            fprintf('📦 Node %d Transmitted Packet ID %d at %.10f seconds\n', n, UniquePktID, Tx_Timestamps(pkt));
            if n == 1
                TotalTxPacketsRome = TotalTxPacketsRome + 1;
            elseif n == 2
                TotalTxPacketsMilan = TotalTxPacketsMilan + 1;
            elseif n == 3
                 TotalTxPacketsVenice = TotalTxPacketsVenice + 1;
            end

        end
            %ine Probabilities for Packet Loss
        Header_Loss_Prob = 0.5;   % 10% chance to lose a header
        Fragment_Loss_Prob = 0.5; % 15% chance to lose a fragment

        % 🚀 **Collision Detection & Fragment-Based Tracking**
        target_collided = zeros(1, fragment_length);  % Track collisions per fragment
        target_discarded = zeros(1, fragment_length); % Track discarded packets due to capture effect

        % Simulate random header loss
        for h = 1:Header_N_DR8
            if rand() < Header_Loss_Prob
                target_collided(h) = 1;  % Mark header as lost
            end
        end

% Simulate random fragment loss
        for frag = (Header_N_DR8+2):fragment_length
            if rand() < Fragment_Loss_Prob
                target_collided(frag) = 1;  % Mark fragment as lost
            end
        end% ✅ Merge retransmissions with original satellite buffer
for s = 1:Total_Sats
    Sat_Receive_Times{s} = [Sat_Receive_Times{s}; Retrans_Sat_Receive_Times{s}];
end


       for s = Visible_Sats
            if ~isempty(Sat_Receive_Times{s})
        % Extract Packet IDs and Arrival Times
            sat_packet_data = Sat_Receive_Times{s}; % Matrix: [PacketID, ArrivalTime]
            sat_packet_data = sortrows(sat_packet_data, 2); % Sort by arrival time
            sat_arrival_times = sat_packet_data(:, 2); % Extract arrival times
            sat_packet_ids = sat_packet_data(:, 1); % Extract Packet IDs

    % 📡 Compute SNR & Apply Rician Fading
            SNR = Tx_Power + Antenna_Gain - Noise_Floor - (20*log10(Distances(n, s, t)/1e3));
            K_factor = 5;
            sigma = sqrt(SNR / (2 * (K_factor + 1))); 
            Fading_SNR = SNR + sigma * randn;
            Decoding_Threshold = 30;  

    % ✅ Detect Collisions
            collisions = sum(diff(sat_arrival_times) < Collision_Threshold);
            total_packets = length(sat_arrival_times);
            TotalCollidedPackets = TotalCollidedPackets + collisions;

            fprintf('💥 %d collisions detected on Satellite %d at Time %.2f min\n', collisions, s, current_time_min);


    % ✅ Display the exact arrival timestamps of packets at this satellite
            formatted_arr = ['[', strtrim(num2str(sat_arrival_times', '%.2f ')), ']'];
            fprintf('⏰ Node %d, Satellite %d arrival packet timings (within %.2f sec): %s\n', ...
            n, s, Time_Step, formatted_arr);

    % ✅ Save arrival times in a formatted string for logging
            pkt_str = sprintf('Sat %d: %s; ', s, formatted_arr);

            if Fading_SNR > Decoding_Threshold
                SuccessRate(n, t) = total_packets - collisions;

        % ✅ If Rome successfully transmits, relay to NodeRM
               if n == 1 || n == 2 || n == 3  % Rome, Milan, Venice
 % Rome or Milan
  % If Rome successfully transmits, relay to NodeRM
    % Extract non-collided packets (packet ID + arrival time)
                non_collided_packets = sat_packet_data(collisions+1:end, :);

    % ✅ Iterate over all non-collided packets
                 for pkt_idx = 1:size(non_collided_packets, 1)
                    packet_id = non_collided_packets(pkt_idx, 1);
                    original_arrival_time = non_collided_packets(pkt_idx, 2);

        % ✅ Iterate over all satellites that received the packet
                     for sat_id = Visible_Sats
            % ✅ Compute Total Delay (Node → Satellite + Satellite → NodeRM)
            %                                                                                                                                                                                                                                                                                                                           
                         total_propagation_delay = (Signal_Delay(n, sat_id, t) + Sat_To_NodeRM_Delay(sat_id, t)) / 60; % Convert sec -> min

            % ✅ Compute Final Corrected Arrival Time at NodeRM
                         nodeRM_reception_time = original_arrival_time + total_propagation_delay;

            % ✅ Store the packet with the correct reception time
                          NodeRM_Packet_Times = [NodeRM_Packet_Times; packet_id, nodeRM_reception_time,n ];
            % ✅ Debugging Output
                        fprintf('📡 Node %d → Sat %d → NodeRM | Packet %d | Tx Time: %.6f min | Arrival at NodeRM: %.6f sec\n', ...
                            n, sat_id, packet_id, original_arrival_time, nodeRM_reception_time);
                    end
                 end
                end

             else
                Collisions(n, t) = collisions;
            end
            else
                fprintf('⏰ Node %d, Satellite %d: No packet arrivals during this time step.\n', n, s);
                pkt_str = sprintf('Sat %d: []; ', s);
            end

        % ✅ Save packet reception logs for Rome & Milan
% Save packet reception logs for Rome & Milan
            if n == 1
                Rome_PktReception{t} = [Rome_PktReception{t}; {UniquePktID, arrival_time}];
                elseif n == 2
                Milan_PktReception{t} = [Milan_PktReception{t}; {UniquePktID, arrival_time}];
                elseif n == 3
                Venice_PktReception{t} = [Venice_PktReception{t}; {UniquePktID, arrival_time}];
            end

        % ✅ Debugging Output
          fprintf('📊 Node %d transmitted %d packets, %d collisions\n', n, Num_Packets, Collisions(n, t));
        end

    % 🚀 **Decoding at NodeRM with Fragment & Header Validation**
   % 🚀 **Decoding at NodeRM with Detailed Failure Analysis**
% 🚀 **Decoding at NodeRM with Detailed Failure Analysis**
 % 🚀 **Decoding at NodeRM with Detailed Failure Analysis**
    % 🚀 **Decoding at NodeRM with Detailed Failure Analysis**
   % ACKedPackets = containers.Map('KeyType','double','ValueType','logical');
    if ~isempty(NodeRM_Packet_Times)
        RawPacketArrivalCounter = RawPacketArrivalCounter + size(NodeRM_Packet_Times, 1);

        NodeRM_Packet_Times = sortrows(NodeRM_Packet_Times, 2);
        % Count total arrivals before filtering duplicates
        % Sort all arrivals by time
        NodeRM_Packet_Times = sortrows(NodeRM_Packet_Times, 2);  

% Save total arrivals before filtering duplicates
        total_rm_arrivals = size(NodeRM_Packet_Times, 1);

% Keep only first arrival of each packet
        [~, unique_idx] = unique(NodeRM_Packet_Times(:,1), 'first');
        NodeRM_Packet_Times = NodeRM_Packet_Times(unique_idx, :);
        AllSeenPacketIDs = unique([AllSeenPacketIDs; NodeRM_Packet_Times(:,1)]);

% Count how many duplicates were ignored
        ignored_duplicates = total_rm_arrivals - size(NodeRM_Packet_Times, 1);
        TotalIgnoredNodeRM = TotalIgnoredNodeRM + ignored_duplicates;

        NodeRM_Visible_Sats = Sat_IDs{3, t};
        common_sats_node1 = intersect(NodeRM_Visible_Sats, Sat_IDs{1, t});
        common_sats_node2 = intersect(NodeRM_Visible_Sats, Sat_IDs{2, t});
        common_sats_node3 = intersect(NodeRM_Visible_Sats, Sat_IDs{3, t});
        common_sats = [common_sats_node1, common_sats_node2,common_sats_node3];


        if ~isempty(common_sats)
            NodeRM_SNR = Tx_Power + Antenna_Gain - Noise_Floor - (20*log10(Distances(3, common_sats(1), t)/1e3));
            sigma_rm = sqrt(NodeRM_SNR / (2 * (5 + 1)));  
            Fading_SNR_RM = NodeRM_SNR + sigma_rm * randn;

            Success_header = Header_N_DR8 - length(nonzeros(target_collided(1:Header_N_DR8)));  
            Threshold = fragment_length - round(fragment_PHY_length * (1 - Code_Rate)) - Header_N_DR8 - 1;
            Success_fragment = fragment_length - length(nonzeros(target_collided((Header_N_DR8 + 2):end))) - Header_N_DR8 - 1;

            if Success_header < 1 || Success_fragment < Threshold || Fading_SNR_RM <= 30
                reason = 'UNKNOWN';
                if Success_header < 1
                  Loss_MissingHeaders = Loss_MissingHeaders + 1;
                elseif Success_fragment < Threshold
                    Loss_InsufficientFragments = Loss_InsufficientFragments + 1;
                elseif Fading_SNR_RM <= 30
                    Loss_LowSNR = Loss_LowSNR + 1;
                else
                    Loss_Other = Loss_Other + 1;
                end

                fprintf('❌ NodeRM failed at %.2f min: %s\n', current_time_min, reason);

                for pkt_idx = 1:size(NodeRM_Packet_Times, 1)
                    pid = NodeRM_Packet_Times(pkt_idx, 1);
                    if isKey(NodeRM_PacketHistory, pid)
                        NodeRM_PacketHistory(pid) = NodeRM_PacketHistory(pid) + 1;
                    else
                        NodeRM_PacketHistory(pid) = 1;
                    end
                    TotalPacketsReceived = TotalPacketsReceived + size(NodeRM_Packet_Times, 1);
                    packet_id = NodeRM_Packet_Times(pkt_idx, 1);
                    originating_node = NodeRM_Packet_Times(pkt_idx, 3);
                    if ~isKey(NACKedPackets, packet_id)
                        NACKedPackets(packet_id) = true;
                    end


                    fprintf('❌ NACK sent for Packet %d from Node %d at %.2f sec\n', packet_id, originating_node, current_time_min);
                    %if ~isKey(CumulativeACKedPackets, packet_id)
                     %   CumulativeACKedPackets(packet_id) = true;
                    %end

                    if originating_node == 1
                        Rome_NACK_Count = Rome_NACK_Count + 1;
                    elseif originating_node == 2
                        Milan_NACK_Count = Milan_NACK_Count + 1;
                    elseif originating_node == 3
                        Venice_NACK_Count = Venice_NACK_Count + 1;
                    end

                    
                    queue = retransmissionQueue{n};  % Using only Milan
                    ...
                    retransmissionQueue{n} = queue;
                     RetransmittedPackets(packet_id) = true;

                if isempty(queue)
                    idx = [];
                    else
                        idx = find(queue(:,1) == packet_id, 1);
                end
                    if isempty(idx)
                        if maxRetransmissions > 1
                            queue(end+1, :) = [packet_id, 1, current_time_sec + retransmissionDelay];
                            fprintf('↩️ Packet %d from Node %d queued for retransmission in %.0f sec (attempt 2)\n', packet_id, originating_node, retransmissionDelay);
                        end
                    else
                        attemptsDone = queue(idx, 2) + 1;
                        if attemptsDone >= maxRetransmissions
                            fprintf('🚫 Packet %d from Node %d reached max attempts. Dropping.\n', packet_id, originating_node);
                            queue(idx, :) = [];
                        else
                            queue(idx, 2) = attemptsDone;
                            queue(idx, 3) = current_time_sec + retransmissionDelay;
                            fprintf('↩️ Packet %d from Node %d will be retried in %d sec (attempt %d)\n', packet_id, originating_node, retransmissionDelay, attemptsDone+1);
                        end
                    end
                    retransmissionQueue{originating_node} = queue;
                    RetransmittedPackets(packet_id) = true;

                end
            else
                Received_Packets_NodeRM(t) = size(NodeRM_Packet_Times, 1);
                fprintf('✅ NodeRM successfully received packets at %.2f min:\n', current_time_min);

                for pkt_idx = 1:size(NodeRM_Packet_Times, 1)
                    packet_id = NodeRM_Packet_Times(pkt_idx, 1);
                   if isKey(CumulativeACKedPackets, packet_id)
                         continue;  % Already ACKed globally
                    end
                    CumulativeACKedPackets(packet_id) = true;
                    original_arrival_time = NodeRM_Packet_Times(pkt_idx, 2);
                    originating_node = NodeRM_Packet_Times(pkt_idx, 3);

                    ack_time = original_arrival_time + 0.1;
                    fprintf('✅ ACK sent for Packet %d from Node %d at %.2f min\n', packet_id, originating_node, ack_time);
                    %if ~isKey(CumulativeACKedPackets, packet_id)
                     %    CumulativeACKedPackets(packet_id) = true;
                    %end
                    ACKedPackets(packet_id) = true;
                    if isKey(RetransmittedPackets, packet_id)
                         Retrans_ACKed(packet_id) = true;
                    end

                    if isKey(NodeRM_PacketHistory, packet_id)
                        NodeRM_PacketHistory(packet_id) = NodeRM_PacketHistory(packet_id) + 1;
                    else
                        NodeRM_PacketHistory(packet_id) = 1;
                    end
                    
                    if originating_node == 1
                        Rome_ACK_Count = Rome_ACK_Count + 1;
                    elseif originating_node == 2
                        Milan_ACK_Count = Milan_ACK_Count + 1;
                    elseif originating_node == 3
                        Venice_ACK_Count = Venice_ACK_Count + 1;
                    end



                    if originating_node <= Nodes-1
                        if ~isempty(retransmissionQueue{originating_node})
                            idx = find(retransmissionQueue{originating_node}(:,1) == packet_id, 1);
                        else
                            idx = [];
                        end
                         if ~isempty(idx)
                            attempts_total = retransmissionQueue{originating_node}(idx, 2) + 1;
                            fprintf('✅ Packet %d from Node %d acknowledged after %d attempts. Removing from retransmission queue.\n', packet_id, originating_node, attempts_total);
                            retransmissionQueue{originating_node}(idx, :) = [];
                         end
                    end

                            if originating_node == 1
                                Rome_PktReception{t} = [Rome_PktReception{t}; {packet_id, 'ACK'}];
                                Rome_RX_Count = Rome_RX_Count + 1;
                            elseif originating_node == 2
                                Milan_PktReception{t} = [Milan_PktReception{t}; {packet_id, 'ACK'}];
                                Milan_RX_Count = Milan_RX_Count + 1;
                            elseif originating_node == 3
                                Venice_PktReception{t} = [Venice_PktReception{t}; {packet_id, 'ACK'}];
                                Venice_RX_Count = Venice_RX_Count + 1;
                            end

                end
               end
           else
            hasRome = ~isempty(common_sats_node1);
            hasMilan = ~isempty(common_sats_node2);
                if ~hasRome && ~hasMilan
                    Loss_NoCommonSatellite = Loss_NoCommonSatellite + size(NodeRM_Packet_Times, 1);

                    fprintf('❌ NodeRM sees no common satellites with either Rome or Milan at %.2f min\n', current_time_min);
                 elseif ~hasRome
                    fprintf('❌ NodeRM sees no common satellites with Rome at %.2f min\n', current_time_min);
                 elseif ~hasMilan
                    fprintf('❌ NodeRM sees no common satellites with Milan at %.2f min\n', current_time_min);
                end
       end

        end
     end
 

end



disp(array2table(Visible_Sat_Matrix, 'VariableNames', {'Time_Min','Rome_Sats','Milan_Sats','NodeRM_Sats'}));
% ✅ Define Excel File Path
outputFile = fullfile(pwd, 'Visible_Satellites_Log.xlsx');  % Save in current directory

% ✅ Convert Data to Table
Visible_Sat_Table = array2table(Visible_Sat_Matrix, ...
    'VariableNames', {'Time_Min', 'Rome_Sats', 'Milan_Sats', 'NodeRM_Sats'});

% ✅ Write to Excel File
writetable(Visible_Sat_Table, outputFile, 'Sheet', 'Visibility Data');

% ✅ Confirm Save
fprintf('📄 Visibility data saved to: %s\n', outputFile);
%% Build a detailed table containing visible satellite IDs and packet reception times
Time_Min = round((Time_Vector)' / 60, 1);

% ✅ Convert cell arrays to string format for Excel compatibility
Rome_PktReception = cellfun(@(x) strjoin(string(x), ', '), Rome_PktReception, 'UniformOutput', false);
Milan_PktReception = cellfun(@(x) strjoin(string(x), ', '), Milan_PktReception, 'UniformOutput', false);
NodeRM_PktReception = cellfun(@(x) strjoin(string(x), ', '), NodeRM_PktReception, 'UniformOutput', false);

% ✅ Convert Satellite IDs into readable strings
Rome_Sat_IDs_str = cellfun(@(x) mat2str(x), Sat_IDs(1,:)', 'UniformOutput', false);
Milan_Sat_IDs_str = cellfun(@(x) mat2str(x), Sat_IDs(2,:)', 'UniformOutput', false);
NodeRM_Sat_IDs_str = cellfun(@(x) mat2str(x), Sat_IDs(3,:)', 'UniformOutput', false);

% ✅ Build the final table for Excel export
DetailedTable = table(Time_Min, Rome_Sat_IDs_str, Milan_Sat_IDs_str, NodeRM_Sat_IDs_str, ...
    Rome_PktReception, Milan_PktReception, NodeRM_PktReception, ...
    'VariableNames', {'Time_Min','Rome_Sat_IDs','Milan_Sat_IDs','NodeRM_Sat_IDs', ...
    'Rome_PktReception','Milan_PktReception','NodeRM_PktReception'});

% ✅ Write the modified table to Excel
%writetable(DetailedTable, filename, 'Sheet', 'DetailedResults');
%fprintf('✅ Detailed results saved to: %s\n', filename);


%% Save DetailedTable to Excel with a specified path
% Specify the folder path (change this to your desired folder)
folderPath = 'D:\thesis\walker\Analysis-and-Simulation-of-LoRaWAN-LR-FHSS-main (1)\Analysis-and-Simulation-of-LoRaWAN-LR-FHSS-main';
if ~exist(folderPath, 'dir')
    mkdir(folderPath);
end
filename = fullfile(folderPath, 'DetailedResults.xlsx');
writetable(DetailedTable, filename, 'Sheet', 'DetailedResults');
fprintf('Detailed results saved to: %s\n', filename);

%% 📊 Final ResultsTotal_ACKs = Rome_ACK_Count + Milan_ACK_Count;
% Final Stats Print
% 📊 Final Stats Summary
all_counts = cell2mat(values(NodeRM_PacketHistory));
duplicates = sum(all_counts > 1);
unique_ids = NodeRM_PacketHistory.Count;

Total_ACKs = Rome_ACK_Count + Milan_ACK_Count + Venice_ACK_Count;
Total_NACKs = Rome_NACK_Count + Milan_NACK_Count + Venice_NACK_Count;
Total_Processed = Total_ACKs + Total_NACKs;

fprintf('\n📊 NodeRM Raw Packet Arrival Stats:\n');
fprintf('\n📨 Total Raw Packet Arrivals at NodeRM (before filtering): %d\n', RawPacketArrivalCounter);
fprintf('🔁 Duplicate Packet Appearances: %d\n', duplicates);
fprintf('📦 Unique Packet IDs Seen Overall: %d\n', unique_ids);

fprintf('\n📊 NodeRM Packet Summary:\n');
fprintf('🏛️ Rome (Node 1):  ACKed = %d,  NACKed = %d\n', Rome_ACK_Count, Rome_NACK_Count);
fprintf('🏙️ Milan (Node 2): ACKed = %d,  NACKed = %d\n', Milan_ACK_Count, Milan_NACK_Count);
fprintf('🏖️ Venice (Node 3): ACKed = %d, NACKed = %d\n', Venice_ACK_Count, Venice_NACK_Count);
fprintf('📦 Total Unique Packets ACKed/NACKed by NodeRM: %d\n', Total_Processed);

fprintf('✅ Overall Success Rate for Rome: %.2f%%\n', 100 * Rome_ACK_Count / max(1, Rome_ACK_Count + Rome_NACK_Count));
fprintf('✅ Overall Success Rate for Milan: %.2f%%\n', 100 * Milan_ACK_Count / max(1, Milan_ACK_Count + Milan_NACK_Count));
fprintf('✅ Overall Success Rate for Venice: %.2f%%\n', 100 * Venice_ACK_Count / max(1, Venice_ACK_Count + Venice_NACK_Count));



fprintf('\n❌ Packet Loss Breakdown at NodeRM:\n');
fprintf('\n📉 Total Packet Collisions Detected: %d\n',TotalCollidedPackets);

fprintf('🚫 No Common Satellite:      %d\n', Loss_NoCommonSatellite);
fprintf('🚫 Missing Headers:          %d\n', Loss_MissingHeaders);
fprintf('🚫 Insufficient Fragments:   %d\n', Loss_InsufficientFragments);
fprintf('🚫 Low SNR:                  %d\n', Loss_LowSNR);
fprintf('❓ Unknown/Other Reasons:     %d\n', Loss_Other);

total_losses = Loss_NoCommonSatellite + Loss_MissingHeaders + Loss_InsufficientFragments + Loss_LowSNR + Loss_Other;
fprintf('📦 Total Packet Loss Events: %d\n', total_losses);


fprintf('\n🗑️ Total Packet Copies Ignored at NodeRM (due to duplicates): %d\n', TotalIgnoredNodeRM);

fprintf('\n🔁 Unique Packet IDs ACKed: %d\n', CumulativeACKedPackets.Count);  % should be 386
fprintf('❌ Unique Packet IDs NACKed: %d\n', NACKedPackets.Count);           % should be 77
fprintf('📦 Total Processed Unique Packets: %d\n', CumulativeACKedPackets.Count + NACKedPackets.Count); % should be 463

fprintf('\n📤 Total Transmissions:\n');
fprintf('🏛️ Rome (Node 1):  %d packets transmitted\n', TotalTxPacketsRome);
fprintf('🏙️ Milan (Node 2): %d packets transmitted\n', TotalTxPacketsMilan);

ACKedIDs = cell2mat(keys(ACKedPackets));
RetransmittedIDs = cell2mat(keys(RetransmittedPackets));

first_try_ACKs = setdiff(ACKedIDs, RetransmittedIDs);
after_retx_ACKs = intersect(ACKedIDs, RetransmittedIDs);

fprintf('✅ ACKed on First Try: %d packets\n', length(first_try_ACKs));
fprintf('🔁 ACKed After Retransmission: %d packets\n', length(after_retx_ACKs));



% 🔁 Print ACKed Packet IDs
acked_ids = cell2mat(keys(CumulativeACKedPackets));
fprintf('\n📦 Packet IDs Successfully ACKed:\n');
for i = 1:length(acked_ids)
    fprintf('%5d ', acked_ids(i));
    if mod(i, 13) == 0  % Print 13 per row
        fprintf('\n');
    end
end
fprintf('\n✅ Total ACKed: %d packets\n', numel(acked_ids));

% ❌ Print NACKed Packet IDs
nacked_ids = cell2mat(keys(NACKedPackets));
fprintf('\n❌ Packet IDs NACKed:\n');
for i = 1:length(nacked_ids)
    fprintf('%5d ', nacked_ids(i));
    if mod(i, 13) == 0  % Print 13 per row
        fprintf('\n');
    end
end
fprintf('\n❌ Total NACKed: %d packets\n', numel(nacked_ids));

retx_ids = cell2mat(keys(RetransmittedPackets));
fprintf('\n🔁 Packet IDs Retransmitted at least once:\n');
for i = 1:length(retx_ids)
    fprintf('%5d ', retx_ids(i));
    if mod(i, 13) == 0
        fprintf('\n');
    end
end
fprintf('\n🔁 Total Retransmitted Packets: %d\n', length(retx_ids));



% Count how many retransmitted packets got ACKed
Retrans_ACKed_Count = Retrans_ACKed.Count;
Retrans_Total = RetransmittedPackets.Count;
Retrans_NACKed_Count = Retrans_Total - Retrans_ACKed_Count;

fprintf('\n🔁 Total Retransmitted Packets: %d\n', Retrans_Total);
fprintf('✅ Retransmitted and ACKed: %d\n', Retrans_ACKed_Count);
fprintf('🚫 Retransmitted and Dropped (NACKed): %d\n', Retrans_NACKed_Count);

%fprintf('✅ Overall Success Rate for Rome: %.2f%%\n', mean(SuccessRate(1, :)) / Num_Packets * 100);
%fprintf('✅ Overall Success Rate for Milan: %.2f%%\n', mean(SuccessRate(2, :)) / Num_Packets * 100);
%fprintf('📡 Total Packets Successfully Received by NodeRM: %d\n', sum(Received_Packets_NodeRM));


fprintf('🏖️ Venice (Node 3): %d packets transmitted\n', TotalTxPacketsVenice);

toc;

%% GRAPH PLOTTING

% Create a common time axis (in minutes)
time_minutes = Visible_Sat_Matrix(:, 1);

% Graph 1: Collisions Over Time for Rome (Node 1) and Milan (Node 2)
%figure;
plot(time_minutes, Collisions(1, :), 'r-o', 'LineWidth', 1.5, 'MarkerSize', 8); hold on;
plot(time_minutes, Collisions(2, :), 'b-o', 'LineWidth', 1.5, 'MarkerSize', 8);
xlabel('Time (min)'); ylabel('Number of Collisions');
title('Collisions over Time for Rome and Milan');
legend('Rome (Node 1)', 'Milan (Node 2)'); grid on;

% Graph 2: Successful Transmissions Over Time for Rome and Milan
figure;
plot(time_minutes, SuccessRate(1, :), 'r-o', 'LineWidth', 1.5, 'MarkerSize', 8); hold on;
plot(time_minutes, SuccessRate(2, :), 'b-o', 'LineWidth', 1.5, 'MarkerSize', 8);
xlabel('Time (min)'); ylabel('Successful Transmissions');
title('Successful Transmissions over Time for Rome and Milan');
legend('Rome (Node 1)', 'Milan (Node 2)'); grid on;

% Graph 3: NodeRM Packet Reception over Time
%figure;
stem(time_minutes, Received_Packets_NodeRM, 'g', 'LineWidth', 1.5, 'Marker', 'o');
xlabel('Time (min)'); ylabel('NodeRM Reception (1 = Received)');
title('NodeRM Packet Reception over Time'); grid on;



% ✅ Check if Latitudes and Longitudes exist before plotting
if exist('Latitudes', 'var') && exist('Longitudes', 'var')
    figure;
    hold on;
    grid on;
    
    % 🌍 **Plot Ground Stations**
    scatter(Node_Coordinates(:, 2), Node_Coordinates(:, 1), 100, 'ro', 'filled');  % Red markers for nodes
    text(Node_Coordinates(:, 2) + 1, Node_Coordinates(:, 1), {'Rome', 'Milan','Venice', 'NodeRM'}, 'FontSize', 12);

    xlabel('Longitude (°)');
    ylabel('Latitude (°)');
    title('2D Animated Ground Tracks of Satellites');
    xlim([-180, 180]);
    ylim([-90, 90]);

    % 🌟 **Initialize Satellite Plot Objects**
    sat_plots = gobjects(Num_Satellites, 1);
    ground_tracks = gobjects(Num_Satellites, 1);

    for s = 1:Num_Satellites
        % **Plot empty ground track (will update over time)**
        ground_tracks(s) = plot(Longitudes(s, 1), Latitudes(s, 1), 'b--', 'LineWidth', 1); % Dashed line for ground track
        sat_plots(s) = plot(Longitudes(s, 1), Latitudes(s, 1), 'bo', 'MarkerSize', 8, 'MarkerFaceColor', 'b'); % Blue circles for satellites
    end

    % 🛰️ **Animate the Satellite Movement**
    for t = 1:num_steps
        for s = 1:Num_Satellites
            % Update satellite positions in the plot
            set(sat_plots(s), 'XData', Longitudes(s, t), 'YData', Latitudes(s, t));

            % **Update ground track by plotting past positions**
            set(ground_tracks(s), 'XData', Longitudes(s, 1:t), 'YData', Latitudes(s, 1:t));
        end

        % 📌 **Update Plot Title with Time**
        title(sprintf('2D Animated Ground Tracks of Satellites (Time: %.2f min)', Time_Vector(t) / 60));

        pause(0.1);  % Small pause for animation effect
    end

    hold off;
else
    fprintf('⚠️ Warning: Latitudes and Longitudes are not available for plotting.\n');
end
diary off;  % Stop saving the console output