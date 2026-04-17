%% balance_lqr.m
% 任务5：旋转倒立摆 LQR 最优控制稳摆
%
% 用法：
%   1. 在MATLAB中运行本脚本
%   2. 脚本将输出 K 到工作区
%   3. 打开 q_qube3_swingup.slx，运行仿真或连接硬件
%
% 控制律：u = -K*x
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

%% LQR 权重矩阵
% Q：状态权重矩阵（越大对该状态误差惩罚越强，抗干扰越强）
% R：控制输入权重（越大控制量越保守/节能）
%
% 对角元素对应：[theta权重, alpha权重, theta_dot权重, alpha_dot权重]
% 可调参数：增大 Q(2,2)（alpha 权重）使摆角恢复更快

Q = diag([1, 1, 1, 1]);   % 各状态等权重，可自行调节
R = 1;                     % 控制输入权重

%% 求 LQR 最优增益
K = lqr(A, B, Q, R);
fprintf('--- LQR 控制结果 ---\n');
fprintf('Q = diag([%g, %g, %g, %g]),  R = %g\n', Q(1,1), Q(2,2), Q(3,3), Q(4,4), R);
fprintf('K = [%.4f, %.4f, %.4f, %.4f]\n', K(1), K(2), K(3), K(4));

% 输出闭环极点
cl_poles = eig(A - B*K);
fprintf('LQR 闭环极点:\n');
for i = 1:length(cl_poles)
    fprintf('  p%d = %.4f %+.4fj\n', i, real(cl_poles(i)), imag(cl_poles(i)));
end

%% 响应仿真对比（极点配置前 vs LQR）
% "配置前"：使用 setup_swingup.m 中的原始 K
K_orig = [1.000, 26.72, 0.8269, 2.214];

sys_before  = ss(A - B*K_orig, zeros(4,1), C, D);
sys_lqr     = ss(A - B*K,      zeros(4,1), C, D);

% 初始条件：摆杆偏离竖直 5°
x0 = [0; deg2rad(5); 0; 0];
t  = 0:0.001:2;

[y_before, t_before] = initial(sys_before, x0, t);
[y_lqr,    t_lqr   ] = initial(sys_lqr,    x0, t);

%% 绘图
figure('Name', 'LQR 最优控制响应对比', 'NumberTitle', 'off');

subplot(2, 1, 1);
plot(t_before, rad2deg(y_before(:,2)), 'r--', 'LineWidth', 1.5);
hold on;
plot(t_lqr,    rad2deg(y_lqr(:,2)),    'b-',  'LineWidth', 2);
yline(0, 'k:', 'LineWidth', 0.8);
xlabel('时间 (s)');
ylabel('摆角 \alpha (deg)');
title('摆角响应对比（极点配置前 vs LQR）');
legend('配置前（原始 K）', ['LQR K，Q=diag(' num2str(diag(Q)') ')'], 'Location', 'best');
grid on;

subplot(2, 1, 2);
plot(t_before, rad2deg(y_before(:,1)), 'r--', 'LineWidth', 1.5);
hold on;
plot(t_lqr,    rad2deg(y_lqr(:,1)),    'b-',  'LineWidth', 2);
yline(0, 'k:', 'LineWidth', 0.8);
xlabel('时间 (s)');
ylabel('转臂角 \theta (deg)');
title('转臂角响应对比（极点配置前 vs LQR）');
legend('配置前（原始 K）', ['LQR K，Q=diag(' num2str(diag(Q)') ')'], 'Location', 'best');
grid on;

fprintf('\nK 已写入工作区，可直接运行 q_qube3_swingup.slx。\n');
fprintf('（Simulink Balance Control 模块会自动读取工作区中的 K）\n');
fprintf('\n提示：可修改 Q 对角元素值，Q 越大对应状态抗干扰越强。\n');
