%% balance_pole_placement.m
% 任务4：旋转倒立摆极点配置稳摆控制
%
% 用法：
%   1. 在MATLAB中运行本脚本
%   2. 脚本将输出 K 到工作区
%   3. 打开 q_qube3_swingup.slx，运行仿真或连接硬件
%
% 性能指标：超调量 < 5%，调节时间 < 1s
% 状态向量: x = [theta (转臂角,rad), alpha (摆角,rad), theta_dot, alpha_dot]

%% 加载系统参数（与 setup_swingup.m 保持一致）
qube3_rotpen_param;

%% 线性化状态空间模型（在摆直立平衡点 alpha=0 附近线性化）
A = [0,       0,        1,       0;
     0,       0,        0,       1;
     0,    149.2751, -0.0104,    0;
     0,  -261.6091,  -0.0103,    0];

B = [0; 0; 49.7275; 49.1493];

C = [1 0 0 0;
     0 1 0 0];

D = [0; 0];

%% 可控性检验
Qc = ctrb(A, B);
if rank(Qc) == length(A)
    disp('可控性检验：系统完全可控');
else
    error('系统不可控，无法进行极点配置');
end

%% 期望极点设计
% 超调量 Mp < 5%  =>  阻尼比 zeta >= 0.69
%   由 Mp = exp(-pi*zeta/sqrt(1-zeta^2)) < 0.05 推导
% 调节时间 ts < 1s  =>  zeta*wn > 3
%   由 ts = 3/(zeta*wn) (5%准则) 推导

zeta = 0.8;   % 阻尼比（满足 zeta > 0.69）
wn   = 5.0;   % 自然频率 rad/s（满足 zeta*wn = 4 > 3）

% 验算指标
Mp_predict = exp(-pi*zeta / sqrt(1 - zeta^2)) * 100;
ts_predict = 3 / (zeta * wn);
fprintf('--- 期望性能 ---\n');
fprintf('  超调量: %.1f%% (要求 < 5%%)\n', Mp_predict);
fprintf('  调节时间: %.2f s  (要求 < 1s)\n', ts_predict);

% 主导极点
sigma = zeta * wn;                     % = 4
wd    = wn * sqrt(1 - zeta^2);        % = 3
p1 =  -sigma + 1j*wd;                 % -4 + 3j
p2 =  -sigma - 1j*wd;                 % -4 - 3j

% 非主导极点：放置于主导极点实部的5倍处（对响应影响小）
p3 = -5 * sigma;                       % -20
p4 = -5 * sigma - 5;                   % -25

desired_poles = [p1, p2, p3, p4];
fprintf('\n期望极点: %.1f%+.1fj,  %.1f%+.1fj,  %.1f,  %.1f\n', ...
    real(p1), imag(p1), real(p2), imag(p2), p3, p4);

%% 用 Ackermann 公式求状态反馈增益 K
K = acker(A, B, desired_poles);
fprintf('\n--- 极点配置结果 ---\n');
fprintf('K = [%.4f, %.4f, %.4f, %.4f]\n', K(1), K(2), K(3), K(4));

% 验证闭环极点
cl_poles = eig(A - B*K);
fprintf('闭环极点验证:\n');
fprintf('  %s\n', sprintf('%.4f%+.4fj  ', [real(cl_poles), imag(cl_poles)]'));

%% 响应仿真对比（极点配置前 vs 后）
% "配置前"：使用 setup_swingup.m 中的原始 K
K_orig = [1.000, 26.72, 0.8269, 2.214];

sys_before = ss(A - B*K_orig, zeros(4,1), C, D);
sys_after  = ss(A - B*K,      zeros(4,1), C, D);

% 初始条件：摆杆偏离竖直 5°
x0 = [0; deg2rad(5); 0; 0];
t  = 0:0.001:2;

[y_before, t_before] = initial(sys_before, x0, t);
[y_after,  t_after ] = initial(sys_after,  x0, t);

%% 绘图
figure('Name', '极点配置前后响应对比', 'NumberTitle', 'off');

subplot(2, 1, 1);
plot(t_before, rad2deg(y_before(:,2)), 'r--', 'LineWidth', 1.5);
hold on;
plot(t_after,  rad2deg(y_after(:,2)),  'b-',  'LineWidth', 2);
yline(0, 'k:', 'LineWidth', 0.8);
xlabel('时间 (s)');
ylabel('摆角 \alpha (deg)');
title('摆角响应对比（极点配置前 vs 后）');
legend('配置前（原始 K）', '配置后（极点配置 K）', 'Location', 'best');
grid on;

subplot(2, 1, 2);
plot(t_before, rad2deg(y_before(:,1)), 'r--', 'LineWidth', 1.5);
hold on;
plot(t_after,  rad2deg(y_after(:,1)),  'b-',  'LineWidth', 2);
yline(0, 'k:', 'LineWidth', 0.8);
xlabel('时间 (s)');
ylabel('转臂角 \theta (deg)');
title('转臂角响应对比（极点配置前 vs 后）');
legend('配置前（原始 K）', '配置后（极点配置 K）', 'Location', 'best');
grid on;

fprintf('\nK 已写入工作区，可直接运行 q_qube3_swingup.slx。\n');
fprintf('（Simulink Balance Control 模块会自动读取工作区中的 K）\n');
