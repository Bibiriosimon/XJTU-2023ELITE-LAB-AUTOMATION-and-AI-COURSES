function Quanser_Position_Monitor()
% 实验六 | 直流电机位置监控系统（双列UI / 表盘动画 / 仿真+硬件 / Save对比）
% 关键实现（本版）：
% 1) 单独驱动 HW PID 参数解析失败：修复为 robust parse（空/NaN 自动回退默认），PD 时 Ki=0
% 2) 硬件表盘永远 5Hz 监视：监视器 timer 始终运行；硬件 run 时使用 run 的实时编码器测量刷新
% 3) New Zero 后目标使用新表盘零点：目标(°)解释为“表盘坐标”（相对 ref），绝对目标=ref+输入

%% ========= 0) 清理遗留窗口与定时器 =========
cleanupLocalArtifacts();

%% ========= 1) 默认配置（内部控制 rad；UI/曲线显示 °） =========
cfg = struct();
cfg.board_type       = 'qube_servo3_usb';
cfg.board_identifier = '0';
cfg.encoder_channel  = 0;
cfg.analog_channel   = 0;
cfg.digital_channel  = 0;
cfg.motor_enable     = 1;
cfg.counts_per_rev   = 2048;

cfg.vmax             = 10.0;
cfg.Ts_hw            = 0.01;
cfg.angle_limit      = deg2rad(190);
cfg.samples_in_buffer= max(1, round(0.1 * (1/cfg.Ts_hw)));

cfg.G_num            = 30;
cfg.G_den            = [0.1 1 0];

col = struct( ...
    'bg',     [0.08 0.09 0.11], ...
    'pnl',    [0.13 0.14 0.17], ...
    'pnl2',   [0.10 0.11 0.14], ...
    'axbg',   [0.05 0.05 0.07], ...
    'txt',    [0.92 0.92 0.93], ...
    'muted',  [0.45 0.45 0.48], ...
    'accent', [0.20 0.60 1.00], ...
    'green',  [0.20 0.80 0.40]);

palette = [ ...
    0.20 0.60 1.00; ...
    1.00 0.55 0.20; ...
    0.90 0.25 0.25; ...
    0.60 0.45 0.95; ...
    0.20 0.85 0.70; ...
    0.95 0.90 0.25];

%% ========= 2) 状态变量 =========
st = struct();
st.stopFlag   = false;
st.timerSim   = [];
st.timerHW    = [];
st.board      = [];
st.task       = [];

st.timeScale  = 1.0;
st.simPlayIdx = 1;

st.sim = struct('t',[],'y_rad',[],'cmd_abs_rad',[],'u',[],'Ts',cfg.Ts_hw);
st.hw  = struct('t',[],'pos_abs_rad',[],'cmd_abs_rad',[],'u',[]);

st.runCounter      = 0;
st.colorIdx        = 1;
st.currentColor    = col.accent;
st.historySimLines = gobjects(0);

% 物理零点（编码器 count）
st.zero = struct('isSet', false, 'count0', 0);

% New Zero（仅显示参考；目标输入采用“表盘坐标” => absTarget = ref + targetDial）
st.ref  = struct('isSet', false, 'refAbsDeg', 0);

% 硬件运行缓存
st.hwRun = struct( ...
    'mode','FOLLOW_SIM', ...
    'Ts',cfg.Ts_hw, ...
    'umin',-cfg.vmax,'umax',cfg.vmax, ...
    'cmd_t',[],'cmd_abs_rad',[], ...
    'pid',struct('kp',0,'ki',0,'kd',0,'N',100), ...
    'pidState',struct('I',0,'y_prev',0,'d',0), ...
    't0',[],'lastPlotN',0);

% 监视器（永远 5Hz 更新表盘）
st.mon = struct( ...
    'timer', [], ...
    'board', [], ...
    'task',  [], ...
    'cfg',   [], ...
    'isOpen', false, ...      % 是否占有硬件资源（board/task）
    'isOn',  false, ...       % timer 是否在跑（永远）
    'lastAbsDeg', 0, ...      % 最近一次“真实绝对角”(°)，HW run 时由 tickHW 更新
    'reopenTick', 0);         % 用于控制重连频率

%% ========= 3) UI =========
scr = get(0,'ScreenSize');
W = 1400; H = 860;
app = struct();

app.fig = figure( ...
    'Name','实验六 | 直流电机位置监控系统（表盘NewZero；硬件5Hz监视）', ...
    'NumberTitle','off','MenuBar','none', ...
    'Color',col.bg,'Position',[scr(3)*0.05 scr(4)*0.06 W H], ...
    'CloseRequestFcn',@onClose);
set(app.fig,'Tag','QPM_FIG');

% --- 仿真曲线（绝对角 °） ---
app.axSim = axes('Parent',app.fig,'Units','pixels','Position',[60 500 560 300], ...
    'Color',col.axbg,'XColor',col.txt,'YColor',col.txt);
grid(app.axSim,'on'); hold(app.axSim,'on');
title(app.axSim,'仿真响应（°，绝对角；CW 为正）','Color','w');
xlabel(app.axSim,'Time (s)'); ylabel(app.axSim,'Angle (deg)');
app.lineSimY   = plot(app.axSim, nan, nan, 'Color', st.currentColor, 'LineWidth', 2.6);
app.lineSimCmd = plot(app.axSim, nan, nan, 'r--', 'LineWidth', 1.2);

% --- 硬件曲线（绝对角 °） ---
app.axHW = axes('Parent',app.fig,'Units','pixels','Position',[60 120 560 300], ...
    'Color',col.axbg,'XColor',col.txt,'YColor',col.txt);
grid(app.axHW,'on'); hold(app.axHW,'on');
title(app.axHW,'硬件响应（°，绝对角；CW 为正）','Color','w');
xlabel(app.axHW,'Time (s)'); ylabel(app.axHW,'Angle (deg)');
app.lineHWPos = plot(app.axHW, nan, nan, 'Color', col.green, 'LineWidth', 2.2);
app.lineHWCmd = plot(app.axHW, nan, nan, 'r:', 'LineWidth', 1.2);

% --- 表盘（显示：相对 NewZero；几何：CW+；-180 不标，只保留 180） ---
app.axSimAnim = axes('Parent',app.fig,'Units','pixels','Position',[660 500 300 300], 'Color',col.bg);
app.vizSim = createDialArmDeg(app.axSimAnim, '仿真表盘（相对NewZero；CW+）', col, -st.ref.refAbsDeg);

app.axHWAnim  = axes('Parent',app.fig,'Units','pixels','Position',[660 120 300 300], 'Color',col.bg);
app.vizHW = createDialArmDeg(app.axHWAnim, '硬件表盘（5Hz；相对NewZero；CW+）', col, -st.ref.refAbsDeg);

% --- 控制台 ---
app.pnl = uipanel('Parent',app.fig,'Units','pixels','Position',[990 20 390 820], ...
    'Title','控制台','BackgroundColor',col.pnl,'ForegroundColor','w');

xL = 15; xR = 205; yTop = 760; rowH = 26; gapY = 10; colW = 170;

uicontrol(app.pnl,'Style','text','Position',[xL yTop colW 20],'String','仿真控制参数（仿真 & 硬件跟随）', ...
    'BackgroundColor',col.pnl,'ForegroundColor','w','FontWeight','bold','HorizontalAlignment','left');
uicontrol(app.pnl,'Style','text','Position',[xR yTop colW 20],'String','硬件控制参数（单独驱动）', ...
    'BackgroundColor',col.pnl,'ForegroundColor','w','FontWeight','bold','HorizontalAlignment','left');

y = yTop - 35;
app.popCtrl  = labeledPopup(app.pnl,[xL y colW rowH],'控制器',{'PID','PD'},'PID',@onCtrlType,col);
app.popCmd   = labeledPopup(app.pnl,[xR y colW rowH],'命令类型',{'阶跃(到目标)','正弦(±A)'},'阶跃(到目标)',@(~,~)0,col);

% 左列：仿真PID
yL0 = y - (rowH+gapY);
app.edKp     = labeledEdit(app.pnl,[xL yL0 colW rowH],'Kp', '0.3',col);
app.edKi     = labeledEdit(app.pnl,[xL yL0-1*(rowH+gapY) colW rowH],'Ki', '0.3',col);
app.edKd     = labeledEdit(app.pnl,[xL yL0-2*(rowH+gapY) colW rowH],'Kd', '0.02',col);
app.edN      = labeledEdit(app.pnl,[xL yL0-3*(rowH+gapY) colW rowH],'N(滤波)', '100',col);

% 目标改为“表盘坐标(°)”：NewZero 后按新表盘零点解释
app.edTarget = labeledEdit(app.pnl,[xL yL0-5*(rowH+gapY) colW rowH],'目标(°，表盘)', '90', col);
app.edRunT   = labeledEdit(app.pnl,[xL yL0-6*(rowH+gapY) colW rowH],'时长(s)', '2.0',col);

% 右列：硬件PID
yR0 = y - (rowH+gapY);
app.edHwKp   = labeledEdit(app.pnl,[xR yR0 colW rowH],'HW Kp', '0.3',col);
app.edHwKi   = labeledEdit(app.pnl,[xR yR0-1*(rowH+gapY) colW rowH],'HW Ki', '0.3',col);
app.edHwKd   = labeledEdit(app.pnl,[xR yR0-2*(rowH+gapY) colW rowH],'HW Kd', '0.02',col);
app.edHwN    = labeledEdit(app.pnl,[xR yR0-3*(rowH+gapY) colW rowH],'HW N',  '100',col);

% 板卡参数
yBoard = yR0 - 5*(rowH+gapY);
app.edBoard  = labeledEdit(app.pnl,[xR yBoard colW rowH],'Board', cfg.board_type, col);
app.edID     = labeledEdit(app.pnl,[xR yBoard-1*(rowH+gapY) colW rowH],'ID', cfg.board_identifier, col);
app.edEnc    = labeledEdit(app.pnl,[xR yBoard-2*(rowH+gapY) colW rowH],'Enc_Ch', num2str(cfg.encoder_channel), col);
app.edAna    = labeledEdit(app.pnl,[xR yBoard-3*(rowH+gapY) colW rowH],'Ana_Ch', num2str(cfg.analog_channel), col);
app.edDig    = labeledEdit(app.pnl,[xR yBoard-4*(rowH+gapY) colW rowH],'Dig_Ch', num2str(cfg.digital_channel), col);
app.edVmax   = labeledEdit(app.pnl,[xR yBoard-5*(rowH+gapY) colW rowH],'Vmax', num2str(cfg.vmax), col);
app.edTs     = labeledEdit(app.pnl,[xR yBoard-6*(rowH+gapY) colW rowH],'Ts(s)', num2str(cfg.Ts_hw), col);

app.txtMetrics = uicontrol(app.pnl,'Style','text','Units','pixels','Position',[15 285 360 120], ...
    'String', sprintf('【仿真指标（°，绝对角）】\n超调量: -\n峰值时间: -\n调节时间(2%%): -\n上升时间: -\n稳态误差: -'), ...
    'BackgroundColor',col.pnl2,'ForegroundColor',col.txt,'HorizontalAlignment','left','FontSize',10);

% 按钮
app.btnSim = uicontrol(app.pnl,'Style','pushbutton','Position',[15 235 360 42], 'String','运行仿真', ...
    'BackgroundColor',[0.10 0.40 0.80],'ForegroundColor','w','FontSize',11,'Callback',@onStartSim);

app.btnSave = uicontrol(app.pnl,'Style','pushbutton','Position',[15 190 175 36], 'String','Save', ...
    'BackgroundColor',[0.40 0.40 0.45],'ForegroundColor','w','Callback',@onSave);

app.btnClear= uicontrol(app.pnl,'Style','pushbutton','Position',[200 190 175 36], 'String','Clear', ...
    'BackgroundColor',[0.30 0.30 0.30],'ForegroundColor','w','Callback',@onClear);

app.btnSlow= uicontrol(app.pnl,'Style','pushbutton','Position',[15 145 360 36], 'String','慢动作: 关', ...
    'BackgroundColor',[0.20 0.20 0.25],'ForegroundColor','w','Callback',@onToggleSlow);

app.btnSetZero = uicontrol(app.pnl,'Style','pushbutton','Position',[15 110 360 32], ...
    'String','设置零点（物理零校准）', ...
    'BackgroundColor',[0.35 0.35 0.10],'ForegroundColor','w','Callback',@onSetZero);

app.btnNewZero = uicontrol(app.pnl,'Style','pushbutton','Position',[15 78 360 30], ...
    'String','New Zero（表盘参考零点）', ...
    'BackgroundColor',[0.20 0.25 0.55],'ForegroundColor','w','Callback',@onNewZero);

app.btnHWFollow = uicontrol(app.pnl,'Style','pushbutton','Position',[15 46 360 30], ...
    'String','硬件跟随（用仿真PID）', ...
    'BackgroundColor',[0.15 0.60 0.40],'ForegroundColor','w','Enable','off','Callback',@onStartHWFollow);

app.btnHWSolo = uicontrol(app.pnl,'Style','pushbutton','Position',[15 18 360 30], ...
    'String','单独驱动（用HW PID）', ...
    'BackgroundColor',[0.10 0.55 0.30],'ForegroundColor','w','Enable','on','Callback',@onStartHWSolo);

app.btnStop = uicontrol(app.pnl,'Style','pushbutton','Position',[15 2 360 14], 'String','紧急停止', ...
    'BackgroundColor',[0.70 0.20 0.20],'ForegroundColor','w','Callback',@onStop);

% 日志
app.log = uicontrol(app.fig,'Style','edit','Units','pixels','Position',[60 20 920 80], 'Max',10, ...
    'BackgroundColor',[0.05 0.05 0.05],'ForegroundColor',col.txt, ...
    'Enable','inactive','HorizontalAlignment','left');

appendLog('准备就绪：建议先【设置零点】。硬件表盘监视器将保持 5Hz 更新。NewZero 后，目标输入按表盘坐标解释。');

% 初始化表盘
updateArmDeg(app.vizSim, 0, 0, st.ref.refAbsDeg);
updateArmDeg(app.vizHW,  0, 0, st.ref.refAbsDeg);

% 启动“永远在跑”的监视器 timer（此时可能尚未有零点/硬件资源）
ensureMonitorTimerRunning();

drawnow;

%% ========= 回调 =========
    function onToggleSlow(~,~)
        if st.timeScale == 1.0
            st.timeScale = 0.1;
            set(app.btnSlow,'String','慢动作: 开 (0.1x)','BackgroundColor',[1 0.4 0]);
            appendLog('慢动作 0.1x 已开启。');
        else
            st.timeScale = 1.0;
            set(app.btnSlow,'String','慢动作: 关','BackgroundColor',[0.20 0.20 0.25]);
            appendLog('恢复正常倍速。');
        end
    end

    function onCtrlType(~,~)
        if get(app.popCtrl,'Value')==2
            set(app.edKi,'Enable','off');
            set(app.edHwKi,'Enable','off');
        else
            set(app.edKi,'Enable','on');
            set(app.edHwKi,'Enable','on');
        end
    end

    function onSetZero(~,~)
        if isRunningSimOrHW()
            appendLog('正在运行中，不能设置零点。请先停止。');
            return;
        end
        cfg_local = readHWConfig();
        if isempty(cfg_local)
            appendLog('硬件配置解析失败，无法设置零点。');
            return;
        end

        % 硬件资源可能被监视器占有：先确保监视器释放硬件资源（timer 不停）
        detachMonitorHardware();

        [count_now, ok] = readEncoderCountOnce(cfg_local);
        if ~ok
            appendLog('读取编码器失败，零点未设置。');
            return;
        end

        st.zero.isSet = true;
        st.zero.count0 = count_now;

        % 物理零校准后，默认 ref=0（NewZero 不启用）
        st.ref.isSet = false;
        st.ref.refAbsDeg = 0;

        st.mon.lastAbsDeg = 0;

        rebuildBothDials();

        appendLog(sprintf('物理零点已设置：count0=%d（此刻定义为绝对0°）。', count_now));

        % 重新让监视器占有硬件资源（开始独立读编码器）
        attachMonitorHardwareIfPossible();
    end

    function onNewZero(~,~)
        if ~st.zero.isSet
            appendLog('请先【设置零点】完成物理零校准，再使用 New Zero。');
            return;
        end
        if isRunningSimOrHW()
            appendLog('硬件运行中不建议设置 New Zero。请先停止或等待运行结束。');
            return;
        end

        % 用监视器读（若监视器未占硬件则单次读取）
        cfg_local = readHWConfig();
        if isempty(cfg_local)
            appendLog('硬件配置解析失败。');
            return;
        end

        absDeg = NaN;
        if st.mon.isOpen && ~isempty(st.mon.task)
            try
                c = st.mon.task.read_encoder(1);
                count = double(c(1));
                absDeg = countToAbsDeg(count, st.zero.count0, cfg.counts_per_rev);
            catch
                absDeg = NaN;
            end
        end
        if ~isfinite(absDeg)
            detachMonitorHardware();
            [count_now, ok] = readEncoderCountOnce(cfg_local);
            if ~ok
                appendLog('读取编码器失败，New Zero 未设置。');
                attachMonitorHardwareIfPossible();
                return;
            end
            absDeg = countToAbsDeg(count_now, st.zero.count0, cfg.counts_per_rev);
            attachMonitorHardwareIfPossible();
        end

        absDeg = clamp(absDeg, -rad2deg(cfg.angle_limit), rad2deg(cfg.angle_limit));

        st.ref.isSet = true;
        st.ref.refAbsDeg = absDeg;

        rebuildBothDials();

        appendLog(sprintf('New Zero 已设置：参考零点=当前绝对角 %.2f°。此后目标输入按“表盘坐标”解释。', absDeg));

        % 此刻表盘读数应接近 0°
        updateArmDeg(app.vizHW, deg2rad(absDeg), deg2rad(absDeg), st.ref.refAbsDeg);
    end

    function onStartSim(~,~)
        if isRunningSimOrHW()
            appendLog('已有任务运行中，请先停止。');
            return;
        end
        st.stopFlag = false;

        [simPID, hwPID, ctrlType, cmdMode, Ts, runT, targetDialDeg, targetAbsDeg, cmd_abs_rad, okPID] = readAllParamsAndMakeCmd();
        if ~okPID
            appendLog('PID 参数解析失败：请检查 Kp/Ki/Kd/N。');
            return;
        end
        if isempty(cmd_abs_rad)
            appendLog('命令生成失败（目标/时长/Ts）。');
            return;
        end

        % 颜色
        st.currentColor = palette(st.colorIdx,:);
        st.colorIdx = st.colorIdx + 1;
        if st.colorIdx > size(palette,1), st.colorIdx = 1; end
        set(app.lineSimY,'Color',st.currentColor);

        t = 0:Ts:runT;

        % 离散对象 + PID
        try
            Gc = tf(cfg.G_num, cfg.G_den);
            sysd = c2d(ss(Gc), Ts, 'zoh');
        catch ME
            appendLog(['对象离散化失败: ' ME.message]);
            return;
        end

        vmax = readVmax();
        umin = -vmax; umax = vmax;

        [y_rad, u] = simulateDiscretePID(sysd, simPID, t, cmd_abs_rad, Ts, umin, umax, cfg.angle_limit);

        st.sim.t = t;
        st.sim.y_rad = y_rad;
        st.sim.u = u;
        st.sim.cmd_abs_rad = cmd_abs_rad;
        st.sim.Ts = Ts;

        simInfo = computeMetrics(st.sim.t, st.sim.y_rad, st.sim.cmd_abs_rad);
        set(app.txtMetrics,'String',sprintf(['【仿真指标（°，绝对角）】\n' ...
            '超调量: %.2f%%\n峰值时间: %.3fs\n调节时间(2%%): %.3fs\n上升时间: %.3fs\n稳态误差: %.3f°'], ...
            simInfo.Overshoot, simInfo.PeakTime, simInfo.SettlingTime, simInfo.RiseTime, rad2deg(simInfo.SSE_rad)));

        set(app.lineSimCmd,'XData',t,'YData',rad2deg(cmd_abs_rad));
        set(app.lineSimY,'XData',nan,'YData',nan);

        st.simPlayIdx = 1;
        st.timerSim = timer('Name','QPM_SIM','ExecutionMode','fixedRate','Period',0.03,'TimerFcn',@tickSim);
        start(st.timerSim);

        appendLog(sprintf('仿真启动 | %s | %s | 目标(表盘)=%.1f° -> 绝对=%.1f° | Ts=%.4fs', ...
            ctrlType, ternary(strcmp(cmdMode,'STEP'),'Step','Sine'), targetDialDeg, targetAbsDeg, Ts));

        % 有仿真后允许硬件跟随
        set(app.btnHWFollow,'Enable','on');

        %#ok<NASGU>
        hwPID = hwPID; % 防止 lint 提示
    end

    function tickSim(~,~)
        if st.stopFlag || st.simPlayIdx > numel(st.sim.t)
            stopTimerSafely('sim');
            return;
        end
        idx = floor(st.simPlayIdx);
        set(app.lineSimY,'XData',st.sim.t(1:idx),'YData',rad2deg(st.sim.y_rad(1:idx)));
        updateArmDeg(app.vizSim, st.sim.y_rad(idx), st.sim.cmd_abs_rad(idx), st.ref.refAbsDeg);

        st.simPlayIdx = st.simPlayIdx + max(0.25, 4*st.timeScale);
        drawnow limitrate;
    end

    function onStartHWFollow(~,~)
        if isRunningSimOrHW()
            appendLog('已有任务运行中，请先停止。');
            return;
        end
        if isempty(st.sim.t)
            appendLog('请先运行仿真生成命令，再启动硬件跟随。');
            return;
        end
        if ~st.zero.isSet
            appendLog('建议先【设置零点】再运行硬件，以保证绝对角一致。');
        end

        st.stopFlag = false;

        [simPID, ~, ctrlType] = readPIDOnly();
        if strcmp(ctrlType,'PD'), simPID.ki = 0; end

        cfg_local = readHWConfig();
        if isempty(cfg_local)
            appendLog('硬件配置解析失败。');
            return;
        end

        startHardwareRun('FOLLOW_SIM', simPID, cfg_local, st.sim.t, st.sim.cmd_abs_rad);
    end

    function onStartHWSolo(~,~)
        if isRunningSimOrHW()
            appendLog('已有任务运行中，请先停止。');
            return;
        end
        if ~st.zero.isSet
            appendLog('建议先【设置零点】再运行硬件，以保证绝对角一致。');
        end

        st.stopFlag = false;

        [~, hwPID, ctrlType, cmdMode, Ts, runT, targetDialDeg, targetAbsDeg, cmd_abs_rad, okPID] = readAllParamsAndMakeCmd();
        if ~okPID
            appendLog('HW PID 参数解析失败：请检查 HW Kp/Ki/Kd/N。');
            return;
        end
        if isempty(cmd_abs_rad)
            appendLog('命令生成失败（目标/时长/Ts）。');
            return;
        end

        cfg_local = readHWConfig();
        if isempty(cfg_local)
            appendLog('硬件配置解析失败。');
            return;
        end

        t = 0:Ts:runT;
        startHardwareRun('SOLO_HW', hwPID, cfg_local, t, cmd_abs_rad);

        appendLog(sprintf('单独驱动启动 | %s | %s | 目标(表盘)=%.1f° -> 绝对=%.1f° | Ts=%.4fs', ...
            ctrlType, ternary(strcmp(cmdMode,'STEP'),'Step','Sine'), targetDialDeg, targetAbsDeg, Ts));
    end

    function startHardwareRun(mode, pid, cfg_local, cmd_t, cmd_abs_rad)
        % 监视器 timer 保持运行，但释放监视器对硬件资源的占用，避免冲突
        detachMonitorHardware();

        set(app.lineHWCmd,'XData',cmd_t,'YData',rad2deg(cmd_abs_rad));
        set(app.lineHWPos,'XData',nan,'YData',nan);

        try
            [board, err] = quanser.hardware.hil.open(cfg_local.board_type, cfg_local.board_identifier);
            if err ~= 0
                try hil_print_error(err); catch, end
                appendLog(sprintf('HIL open 失败：err=%d', err));
                return;
            end
            st.board = board;

            samples_in_buffer = max(1, round(0.1 * (1/(cmd_t(2)-cmd_t(1)))));
            [task, err] = st.board.task_create_encoder_reader(samples_in_buffer, cfg_local.encoder_channel);
            if err ~= 0
                try hil_print_error(err); catch, end
                appendLog(sprintf('task_create_encoder_reader 失败：err=%d', err));
                safeCloseHW(cfg_local);
                attachMonitorHardwareIfPossible();
                return;
            end
            st.task = task;

            if ~isnan(cfg_local.digital_channel)
                try st.board.write_digital(cfg_local.digital_channel, cfg.motor_enable); catch, end
            end

            Ts = cmd_t(2)-cmd_t(1);
            clock = 0;
            frequency = max(1, round(1/Ts));
            samples = -1;
            st.task.start(clock, frequency, samples);

            if ~st.zero.isSet
                % 无零点时自动初始化
                try
                    c0 = st.task.read_encoder(1);
                    c0 = double(c0(1));
                    st.zero.isSet = true;
                    st.zero.count0 = c0;
                    appendLog(sprintf('提示：尚未设置零点，已自动用当前 count=%d 作为零点。', c0));
                catch
                    appendLog('零点自动初始化失败：请手动【设置零点】。');
                end
            end

        catch ME
            appendLog(['硬件初始化异常: ' ME.message]);
            safeCloseHW(cfg_local);
            attachMonitorHardwareIfPossible();
            return;
        end

        st.hw.t = [];
        st.hw.pos_abs_rad = [];
        st.hw.cmd_abs_rad = [];
        st.hw.u = [];

        Ts = cmd_t(2)-cmd_t(1);

        st.hwRun.mode = mode;
        st.hwRun.Ts = Ts;
        st.hwRun.umin = -cfg_local.vmax;
        st.hwRun.umax =  cfg_local.vmax;
        st.hwRun.cmd_t = cmd_t;
        st.hwRun.cmd_abs_rad = cmd_abs_rad;
        st.hwRun.pid = pid;
        st.hwRun.pidState = struct('I',0,'y_prev',0,'d',0);
        st.hwRun.t0 = tic;
        st.hwRun.lastPlotN = 0;

        st.timerHW = timer('Name','QPM_HW','ExecutionMode','fixedRate','Period',Ts,'TimerFcn',@tickHW);
        start(st.timerHW);

        appendLog(sprintf('硬件运行启动：MODE=%s | count0=%d | Vmax=%.2f', mode, st.zero.count0, cfg_local.vmax));
    end

    function tickHW(~,~)
        if st.stopFlag
            stopTimerSafely('hw');
            safeCloseHW(readHWConfigSilent());
            appendLog('硬件已停止。');
            attachMonitorHardwareIfPossible();
            return;
        end
        if isempty(st.task) || isempty(st.board)
            stopTimerSafely('hw');
            appendLog('硬件对象无效，停止。');
            attachMonitorHardwareIfPossible();
            return;
        end

        Ts = st.hwRun.Ts;
        tnow = toc(st.hwRun.t0);

        if tnow > st.hwRun.cmd_t(end)
            stopTimerSafely('hw');
            safeCloseHW(readHWConfigSilent());
            appendLog('硬件运行结束。');
            attachMonitorHardwareIfPossible();
            return;
        end

        k = min(numel(st.hwRun.cmd_abs_rad), max(1, floor(tnow/Ts) + 1));
        cmd_abs = st.hwRun.cmd_abs_rad(k);
        cmd_abs = clamp(cmd_abs, -cfg.angle_limit, cfg.angle_limit);

        try
            c = st.task.read_encoder(1);
            count = double(c(1));
        catch ME
            appendLog(['read_encoder 失败: ' ME.message]);
            stopTimerSafely('hw');
            safeCloseHW(readHWConfigSilent());
            attachMonitorHardwareIfPossible();
            return;
        end

        pos_abs = (count - st.zero.count0) * (2*pi) / cfg.counts_per_rev;
        pos_abs = clamp(pos_abs, -cfg.angle_limit, cfg.angle_limit);

        % 更新监视器的“真实角度缓存”，保证硬件 run 时监视器仍 5Hz 刷新且来源真实编码器
        st.mon.lastAbsDeg = rad2deg(pos_abs);

        e = cmd_abs - pos_abs;
        [u, st.hwRun.pidState] = pidStepDOM(e, pos_abs, st.hwRun.pidState, st.hwRun.pid, Ts, st.hwRun.umin, st.hwRun.umax);

        try
            st.board.write_analog(readHWConfigSilent().analog_channel, u);
        catch ME
            appendLog(['write_analog 失败: ' ME.message]);
            stopTimerSafely('hw');
            safeCloseHW(readHWConfigSilent());
            attachMonitorHardwareIfPossible();
            return;
        end

        st.hw.t(end+1)          = tnow;
        st.hw.pos_abs_rad(end+1)= pos_abs;
        st.hw.cmd_abs_rad(end+1)= cmd_abs;
        st.hw.u(end+1)          = u;

        % 曲线刷新（~50Hz）
        if numel(st.hw.t) - st.hwRun.lastPlotN >= max(1, round(0.02/Ts))
            st.hwRun.lastPlotN = numel(st.hw.t);
            set(app.lineHWPos,'XData',st.hw.t,'YData',rad2deg(st.hw.pos_abs_rad));
            updateArmDeg(app.vizHW, pos_abs, cmd_abs, st.ref.refAbsDeg);
            drawnow limitrate;
        end
    end

    function onSave(~,~)
        if isempty(st.sim.t)
            appendLog('Save失败：当前没有仿真数据。');
            return;
        end
        st.runCounter = st.runCounter + 1;

        hs = plot(app.axSim, st.sim.t, rad2deg(st.sim.y_rad), 'Color', col.muted, 'LineWidth', 1.2, 'HandleVisibility','off');
        st.historySimLines(end+1) = hs;
        uistack(app.lineSimY,'top'); uistack(app.lineSimCmd,'top');

        appendLog(sprintf('SAVED[#%d] 留存仿真曲线完成。', st.runCounter));
    end

    function onClear(~,~)
        if ~isempty(st.historySimLines) && any(isgraphics(st.historySimLines))
            delete(st.historySimLines(isgraphics(st.historySimLines)));
        end
        st.historySimLines = gobjects(0);
        appendLog('Clear完成：已清除留存曲线。');
    end

    function onStop(~,~)
        st.stopFlag = true;
        stopTimerSafely('sim');
        stopTimerSafely('hw');

        cfg_local = readHWConfigSilent();
        safeCloseHW(cfg_local);

        % 紧急停止后：监视器仍保持 5Hz（如已设置零点则尝试占用硬件资源）
        attachMonitorHardwareIfPossible();

        appendLog('已停止（紧急停止）。');
    end

    function onClose(~,~)
        st.stopFlag = true;
        stopTimerSafely('sim');
        stopTimerSafely('hw');
        safeCloseHW(readHWConfigSilent());
        stopMonitorAll();
        try delete(app.fig); catch, end
    end

%% ========= 监视器（永远 5Hz 更新表盘） =========
    function ensureMonitorTimerRunning()
        if st.mon.isOn && ~isempty(st.mon.timer) && isvalid(st.mon.timer)
            return;
        end
        st.mon.timer = timer('Name','QPM_MON','ExecutionMode','fixedRate','Period',0.2,'TimerFcn',@tickMonitor);
        start(st.mon.timer);
        st.mon.isOn = true;
    end

    function tickMonitor(~,~)
        if st.stopFlag
            return;
        end

        % 永远刷新硬件表盘（5Hz）
        if isRunningSimOrHW()
            % 硬件 run 时：用 tickHW 写入的 lastAbsDeg（真实编码器来源）
            absDeg = st.mon.lastAbsDeg;
        else
            % 非 run：尽量独立读编码器；读不到就用 lastAbsDeg 兜底
            if st.zero.isSet
                if ~st.mon.isOpen
                    % 限制重连频率：每 1s 尝试一次
                    st.mon.reopenTick = st.mon.reopenTick + 1;
                    if st.mon.reopenTick >= 5
                        st.mon.reopenTick = 0;
                        attachMonitorHardwareIfPossible();
                    end
                end
                if st.mon.isOpen && ~isempty(st.mon.task)
                    try
                        c = st.mon.task.read_encoder(1);
                        count = double(c(1));
                        absDeg = countToAbsDeg(count, st.zero.count0, cfg.counts_per_rev);
                        absDeg = clamp(absDeg, -rad2deg(cfg.angle_limit), rad2deg(cfg.angle_limit));
                        st.mon.lastAbsDeg = absDeg;
                    catch
                        absDeg = st.mon.lastAbsDeg;
                        detachMonitorHardware(); % 读失败就释放，等待下次重连
                    end
                else
                    absDeg = st.mon.lastAbsDeg;
                end
            else
                absDeg = 0; % 未零校准前，显示 0
            end
        end

        updateArmDeg(app.vizHW, deg2rad(absDeg), deg2rad(absDeg), st.ref.refAbsDeg);
        drawnow limitrate;
    end

    function detachMonitorHardware()
        % 释放监视器占用的硬件资源（timer 不停）
        try
            if st.mon.isOpen
                if ~isempty(st.mon.task)
                    try st.mon.task.stop; catch, end
                    try st.mon.task.close; catch, end
                end
                if ~isempty(st.mon.board)
                    try st.mon.board.close; catch, end
                end
            end
        catch
        end
        st.mon.task = [];
        st.mon.board = [];
        st.mon.isOpen = false;
    end

    function attachMonitorHardwareIfPossible()
        % 只有在：已设置零点 且 不在 sim/hw run 时，才占用硬件资源独立读编码器
        if ~st.zero.isSet
            return;
        end
        if isRunningSimOrHW()
            return;
        end
        if st.mon.isOpen
            return;
        end

        cfg_local = readHWConfigSilent();
        if isempty(cfg_local)
            return;
        end

        try
            [board, err] = quanser.hardware.hil.open(cfg_local.board_type, cfg_local.board_identifier);
            if err ~= 0
                try hil_print_error(err); catch, end
                return;
            end
            [task, err] = board.task_create_encoder_reader(1, cfg_local.encoder_channel);
            if err ~= 0
                try hil_print_error(err); catch, end
                try board.close; catch, end
                return;
            end

            if ~isnan(cfg_local.digital_channel)
                try board.write_digital(cfg_local.digital_channel, cfg.motor_enable); catch, end
            end
            task.start(0, 250, -1);

            st.mon.board = board;
            st.mon.task  = task;
            st.mon.cfg   = cfg_local;
            st.mon.isOpen= true;
        catch
            detachMonitorHardware();
        end
    end

    function stopMonitorAll()
        try
            if ~isempty(st.mon.timer) && isvalid(st.mon.timer)
                stop(st.mon.timer); delete(st.mon.timer);
            end
        catch
        end
        st.mon.timer = [];
        st.mon.isOn = false;
        detachMonitorHardware();
    end

%% ========= 参数读取与命令生成（NewZero 后按表盘坐标） =========
    function [simPID, hwPID, ctrlType, cmdMode, Ts, runT, targetDialDeg, targetAbsDeg, cmd_abs_rad, okPID] = readAllParamsAndMakeCmd()
        okPID = true;
        cmd_abs_rad = [];

        ctrlType = getPopupString(app.popCtrl);
        cmdModeUI = getPopupString(app.popCmd);
        if contains(cmdModeUI,'正弦')
            cmdMode = 'SINE';
        else
            cmdMode = 'STEP';
        end

        Ts = parseNum(get(app.edTs,'String'), cfg.Ts_hw);
        if ~isfinite(Ts) || Ts<=0
            okPID = false; return;
        end

        runT = parseNum(get(app.edRunT,'String'), 2.0);
        if ~isfinite(runT) || runT<=0
            okPID = false; return;
        end

        targetDialDeg = parseNum(get(app.edTarget,'String'), 0);

        % PID（robust parse）
        simPID = sanitizePID(struct( ...
            'kp', parseNum(get(app.edKp,'String'), 0), ...
            'ki', parseNum(get(app.edKi,'String'), 0), ...
            'kd', parseNum(get(app.edKd,'String'), 0), ...
            'N',  parseNum(get(app.edN,'String'), 100)), ctrlType);

        hwPID = sanitizePID(struct( ...
            'kp', parseNum(get(app.edHwKp,'String'), 0), ...
            'ki', parseNum(get(app.edHwKi,'String'), 0), ...
            'kd', parseNum(get(app.edHwKd,'String'), 0), ...
            'N',  parseNum(get(app.edHwN,'String'), 100)), ctrlType);

        % 简单有效性检查（kp/kd/N 非法则 fail）
        if ~all(isfinite([simPID.kp simPID.ki simPID.kd simPID.N])) || simPID.N<=0
            okPID = false; return;
        end
        if ~all(isfinite([hwPID.kp hwPID.ki hwPID.kd hwPID.N])) || hwPID.N<=0
            okPID = false; return;
        end

        % 目标解释：输入为“表盘角(°)” => 绝对目标 = refAbsDeg + 输入
        refAbsDeg = st.ref.refAbsDeg;
        if strcmp(cmdMode,'STEP')
            targetAbsDeg = wrapTo180_local(refAbsDeg + targetDialDeg);
        else
            % SINE：围绕 refAbsDeg 振荡，幅度 = |targetDialDeg|
            targetAbsDeg = refAbsDeg; % 中心值（用于日志）
        end

        t = 0:Ts:runT;
        cmd_abs_deg = zeros(size(t));
        switch cmdMode
            case 'SINE'
                A = abs(targetDialDeg);
                f = 0.5;
                cmd_abs_deg = refAbsDeg + A*sin(2*pi*f*t);
            otherwise
                cmd_abs_deg(:) = refAbsDeg + targetDialDeg;
        end

        % wrap + clamp（避免 -180/180 重叠显示；控制仍允许到 ±190）
        cmd_abs_deg = arrayfun(@wrapTo180_local, cmd_abs_deg);
        cmd_abs_rad = deg2rad(cmd_abs_deg);
        cmd_abs_rad = clamp(cmd_abs_rad, -cfg.angle_limit, cfg.angle_limit);
    end

    function [simPID, hwPID, ctrlType] = readPIDOnly()
        ctrlType = getPopupString(app.popCtrl);
        simPID = sanitizePID(struct( ...
            'kp', parseNum(get(app.edKp,'String'), 0), ...
            'ki', parseNum(get(app.edKi,'String'), 0), ...
            'kd', parseNum(get(app.edKd,'String'), 0), ...
            'N',  parseNum(get(app.edN,'String'), 100)), ctrlType);

        hwPID = sanitizePID(struct( ...
            'kp', parseNum(get(app.edHwKp,'String'), 0), ...
            'ki', parseNum(get(app.edHwKi,'String'), 0), ...
            'kd', parseNum(get(app.edHwKd,'String'), 0), ...
            'N',  parseNum(get(app.edHwN,'String'), 100)), ctrlType);
    end

    function pid = sanitizePID(pid, ctrlType)
        % 对 NaN/空输入做默认回退；PD 模式 Ki 强制 0；N<=0 回退 100
        if ~isfinite(pid.kp), pid.kp = 0; end
        if ~isfinite(pid.ki), pid.ki = 0; end
        if ~isfinite(pid.kd), pid.kd = 0; end
        if ~isfinite(pid.N) || pid.N <= 0, pid.N = 100; end
        if strcmp(ctrlType,'PD')
            pid.ki = 0;
        end
        pid.N = max(pid.N, 1);
    end

%% ========= 工具函数 =========
    function rebuildBothDials()
        app.vizSim = createDialArmDeg(app.axSimAnim, '仿真表盘（相对NewZero；CW+）', col, -st.ref.refAbsDeg);
        app.vizHW  = createDialArmDeg(app.axHWAnim,  '硬件表盘（5Hz；相对NewZero；CW+）', col, -st.ref.refAbsDeg);
    end

    function cfg_local = readHWConfig()
        cfg_local = readHWConfigSilent();
        if isempty(cfg_local), return; end
        if any(isnan([cfg_local.encoder_channel cfg_local.analog_channel cfg_local.vmax cfg_local.Ts_hw]))
            cfg_local = [];
        end
        if cfg_local.vmax <= 0 || cfg_local.Ts_hw <= 0
            cfg_local = [];
        end
    end

    function cfg_local = readHWConfigSilent()
        try
            cfg_local = cfg;
            cfg_local.board_type       = strtrim(get(app.edBoard,'String'));
            cfg_local.board_identifier = strtrim(get(app.edID,'String'));
            cfg_local.encoder_channel  = str2double(get(app.edEnc,'String'));
            cfg_local.analog_channel   = str2double(get(app.edAna,'String'));
            cfg_local.digital_channel  = str2double(get(app.edDig,'String'));
            cfg_local.vmax             = str2double(get(app.edVmax,'String'));
            cfg_local.Ts_hw            = str2double(get(app.edTs,'String'));
            if isnan(cfg_local.Ts_hw), cfg_local.Ts_hw = cfg.Ts_hw; end
            if isnan(cfg_local.vmax),  cfg_local.vmax  = cfg.vmax; end
        catch
            cfg_local = [];
        end
    end

    function vmax = readVmax()
        vmax = str2double(get(app.edVmax,'String'));
        if isnan(vmax), vmax = cfg.vmax; end
    end

    function tf = isRunningSimOrHW()
        tf = (~isempty(st.timerSim) && isvalid(st.timerSim)) || (~isempty(st.timerHW) && isvalid(st.timerHW));
    end

    function stopTimerSafely(whichOne)
        try
            if strcmpi(whichOne,'sim') && ~isempty(st.timerSim) && isvalid(st.timerSim)
                stop(st.timerSim); delete(st.timerSim); st.timerSim = [];
            end
        catch
            st.timerSim = [];
        end
        try
            if strcmpi(whichOne,'hw') && ~isempty(st.timerHW) && isvalid(st.timerHW)
                stop(st.timerHW); delete(st.timerHW); st.timerHW = [];
            end
        catch
            st.timerHW = [];
        end
    end

    function safeCloseHW(cfg_local)
        if isempty(cfg_local), cfg_local = cfg; end
        try
            if ~isempty(st.board)
                try st.board.write_analog(cfg_local.analog_channel, 0); catch, end
            end
        catch
        end
        try
            if ~isempty(st.task)
                try st.task.stop; catch, end
                try st.task.close; catch, end
            end
        catch
        end
        try
            if ~isempty(st.board)
                try st.board.close; catch, end
            end
        catch
        end
        st.task  = [];
        st.board = [];
    end

    function appendLog(msg)
        try
            old = get(app.log,'String');
            if ischar(old), old = cellstr(old); end
            new = [old; {['> ' msg]}];
            if numel(new) > 15, new = new(end-14:end); end
            set(app.log,'String',new);
            drawnow limitrate;
        catch
        end
    end

    function s = getPopupString(hPop)
        items = get(hPop,'String');
        idx = get(hPop,'Value');
        if iscell(items), s = items{idx};
        else, s = strtrim(items(idx,:));
        end
    end

    function out = clamp(x, lo, hi)
        out = min(max(x, lo), hi);
    end

    function out = ternary(cond, a, b)
        if cond, out = a; else, out = b; end
    end

    function v = parseNum(str, defaultVal)
        v = str2double(str);
        if ~isfinite(v)
            v = defaultVal;
        end
    end

    function absDeg = countToAbsDeg(count, count0, cpr)
        absDeg = (double(count) - double(count0)) * 360.0 / double(cpr);
    end

    function d = wrapTo180_local(d)
        d = mod(d + 180, 360) - 180;
        % 把 -180 映射到 +180（避免 -180/180 重叠标注）
        if abs(d + 180) < 1e-10
            d = 180;
        end
    end

%% ========= 离散 PID（D on measurement + 导数滤波 + anti-windup） =========
    function [u, pidst] = pidStepDOM(e, y, pidst, pid, Ts, umin, umax)
        kp = pid.kp; ki = pid.ki; kd = pid.kd; N = pid.N;
        Tf = 1/max(N, 1e-9);

        dy = (y - pidst.y_prev);
        d_new = (Tf/(Tf+Ts)) * pidst.d + (kd/(Tf+Ts)) * dy;
        pidst.y_prev = y;
        pidst.d = d_new;

        u_unsat = kp*e + ki*pidst.I - d_new;

        doInt = false;
        if abs(ki) >= 1e-12
            if (u_unsat > umin) && (u_unsat < umax)
                doInt = true;
            elseif (u_unsat >= umax) && (e < 0)
                doInt = true;
            elseif (u_unsat <= umin) && (e > 0)
                doInt = true;
            end
        end
        if doInt
            pidst.I = pidst.I + e * Ts;
        end
        pidst.I = clamp(pidst.I, -50, 50);

        u = kp*e + ki*pidst.I - d_new;
        u = clamp(u, umin, umax);
    end

    function [y_rad, u] = simulateDiscretePID(sysd, pid, t, cmd_abs_rad, Ts, umin, umax, angle_limit)
        A = sysd.A; B = sysd.B; C = sysd.C;
        nx = size(A,1);

        x = zeros(nx,1);
        y_rad = zeros(size(t));
        u     = zeros(size(t));

        pidst = struct('I',0,'y_prev',0,'d',0);

        for k = 1:numel(t)
            yk = C*x;
            yk = clamp(yk, -angle_limit, angle_limit);

            ek = cmd_abs_rad(k) - yk;
            [uk, pidst] = pidStepDOM(ek, yk, pidst, pid, Ts, umin, umax);

            x = A*x + B*uk;

            y_rad(k) = yk;
            u(k)     = uk;
        end
    end

    function info = computeMetrics(t, y_rad, cmd_rad)
        info = struct('Overshoot',NaN,'PeakTime',NaN,'SettlingTime',NaN,'RiseTime',NaN,'SSE_rad',NaN);
        if isempty(t) || isempty(y_rad), return; end
        target = cmd_rad(end);
        try
            si = stepinfo(y_rad, t, target);
            info.Overshoot    = si.Overshoot;
            info.PeakTime     = si.PeakTime;
            info.SettlingTime = si.SettlingTime;
            info.RiseTime     = si.RiseTime;
            info.SSE_rad      = abs(target - y_rad(end));
        catch
            info.SSE_rad = abs(cmd_rad(end) - y_rad(end));
        end
    end

%% ========= 单次读取 encoder（设置零点时用） =========
    function [count_now, ok] = readEncoderCountOnce(cfg_local)
        ok = false;
        count_now = NaN;
        try
            [board, err] = quanser.hardware.hil.open(cfg_local.board_type, cfg_local.board_identifier);
            if err ~= 0
                try hil_print_error(err); catch, end
                return;
            end

            [task, err] = board.task_create_encoder_reader(1, cfg_local.encoder_channel);
            if err ~= 0
                try hil_print_error(err); catch, end
                try board.close; catch, end
                return;
            end

            if ~isnan(cfg_local.digital_channel)
                try board.write_digital(cfg_local.digital_channel, cfg.motor_enable); catch, end
            end

            task.start(0, 100, -1);
            pause(0.02);
            c = task.read_encoder(1);
            count_now = double(c(1));

            try task.stop; catch, end
            try task.close; catch, end
            try board.close; catch, end

            ok = true;
        catch
            ok = false;
        end
    end

%% ========= 表盘（°，CW+；只保留 180 标注，不标 -180） =========
    function viz = createDialArmDeg(ax, tag, colLocal, bgOffsetDeg)
        axes(ax); cla(ax); hold(ax,'on');
        axis(ax,'equal'); xlim(ax,[-1.55 1.55]); ylim(ax,[-1.55 1.55]); axis(ax,'off');

        th = linspace(0,2*pi,200);
        patch(ax, 1.28*cos(th), 1.28*sin(th), [0.15 0.16 0.19], 'EdgeColor', [0.35 0.35 0.38]);

        for deg = -170:10:180
            isMajor = (mod(deg,30)==0);
            r1 = 1.05; r2 = 1.25;
            if isMajor
                lw = 1.4; c = [0.72 0.72 0.74]; r1 = 0.98;
            else
                lw = 0.8; c = [0.45 0.45 0.48];
            end

            angGeom = (-deg) + bgOffsetDeg; % CW+ + 背景偏移
            x1 = r1*cosd(angGeom); y1 = r1*sind(angGeom);
            x2 = r2*cosd(angGeom); y2 = r2*sind(angGeom);
            plot(ax, [x1 x2], [y1 y2], 'Color', c, 'LineWidth', lw);

            if isMajor
                tx = 1.42*cosd(angGeom); ty = 1.42*sind(angGeom);
                text(ax, tx, ty, sprintf('%d°',deg), 'Color',[0.80 0.80 0.82], ...
                    'FontSize',8,'HorizontalAlignment','center','VerticalAlignment','middle');
            end
        end

        plot(ax, [-1.2 1.2],[0 0],'Color',[0.25 0.25 0.28],'LineStyle','--');
        plot(ax, [0 0],[-1.2 1.2],'Color',[0.25 0.25 0.28],'LineStyle','--');

        viz.bgOffsetDeg = bgOffsetDeg;
        viz.armBase = [-0.05 1.10 1.10 -0.05; -0.07 -0.07 0.07 0.07];
        viz.arm = patch(ax, viz.armBase(1,:), viz.armBase(2,:), colLocal.accent, 'EdgeColor','w','LineWidth',1.0);
        viz.tip = plot(ax, 1.10, 0, 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', colLocal.accent);

        viz.ref = plot(ax, [0 1.25], [0 0], 'r--', 'LineWidth', 1.2);

        text(ax, -1.25, 1.45, tag, 'Color','w','FontSize',10,'FontWeight','bold');
        viz.txt = text(ax, -0.95, -1.45, '0.0°', 'Color', colLocal.accent, 'FontSize', 12, 'FontWeight','bold');
        viz.txt2= text(ax, -1.35, -1.25, '', 'Color', [0.75 0.75 0.78], 'FontSize', 9);
    end

    function updateArmDeg(viz, ang_abs_rad, cmd_abs_rad, refAbsDeg)
        absDeg = rad2deg(ang_abs_rad);
        cmdDeg = rad2deg(cmd_abs_rad);

        relDeg = wrapTo180_local(absDeg - refAbsDeg);
        relCmd = wrapTo180_local(cmdDeg - refAbsDeg);

        angGeom = (-relDeg) + viz.bgOffsetDeg;
        refGeom = (-relCmd) + viz.bgOffsetDeg;

        R = [cosd(angGeom) -sind(angGeom); sind(angGeom) cosd(angGeom)];
        newPts = R * viz.armBase;
        set(viz.arm, 'XData', newPts(1,:), 'YData', newPts(2,:));

        tipPos = R * [1.10; 0];
        set(viz.tip, 'XData', tipPos(1), 'YData', tipPos(2));

        set(viz.ref, 'XData', [0 1.25*cosd(refGeom)], 'YData', [0 1.25*sind(refGeom)]);

        set(viz.txt,  'String', sprintf('%.1f°', relDeg));
        set(viz.txt2, 'String', sprintf('Abs: %.1f° | Ref: %.1f°', absDeg, refAbsDeg));
    end

end % ===== main end =====


%% ========= UI 小组件（文件级子函数） =========
function h = labeledEdit(parent, pos, label, default, col)
uicontrol(parent,'Style','text','Position',[pos(1) pos(2) pos(3)*0.48 pos(4)], ...
    'String',label,'BackgroundColor',col.pnl,'ForegroundColor','w','HorizontalAlignment','left');
h = uicontrol(parent,'Style','edit','Position',[pos(1)+pos(3)*0.52 pos(2) pos(3)*0.48 pos(4)], ...
    'String',default,'BackgroundColor',[0.07 0.07 0.09],'ForegroundColor',col.txt);
end

function h = labeledPopup(parent, pos, label, items, default, cb, col)
uicontrol(parent,'Style','text','Position',[pos(1) pos(2) pos(3)*0.48 pos(4)], ...
    'String',label,'BackgroundColor',col.pnl,'ForegroundColor','w','HorizontalAlignment','left');
h = uicontrol(parent,'Style','popupmenu','Position',[pos(1)+pos(3)*0.52 pos(2) pos(3)*0.48 pos(4)], ...
    'String',items,'BackgroundColor',[0.07 0.07 0.09],'ForegroundColor',col.txt,'Callback',cb);
idx = find(strcmp(items,default),1);
if ~isempty(idx), set(h,'Value',idx); end
end

function cleanupLocalArtifacts()
try
    oldFig = findall(0,'Type','figure','Tag','QPM_FIG');
    if ~isempty(oldFig), delete(oldFig); end
catch
end
try
    t1 = timerfindall('Name','QPM_SIM');
    if ~isempty(t1), stop(t1); delete(t1); end
catch
end
try
    t2 = timerfindall('Name','QPM_HW');
    if ~isempty(t2), stop(t2); delete(t2); end
catch
end
try
    t3 = timerfindall('Name','QPM_MON');
    if ~isempty(t3), stop(t3); delete(t3); end
catch
end
end
