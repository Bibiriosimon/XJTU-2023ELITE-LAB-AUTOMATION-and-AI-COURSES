function [] = run_feedforward_experiment()
% XB4前馈控制实验 - 完整命令行仿真脚本
% 使用方法: 在MATLAB命令行输入 run_feedforward_experiment 回车即可

%% 1. 初始化
clc; close all;
fprintf('============================================\n');
fprintf('   XB4机械臂 前馈控制实验\n');
fprintf('============================================\n');

cd 'C:\Users\Administrator\Desktop\大二三\智能机器人技术\前馈控制实验';
mkdir('结果图');

%% 2. 加载XB4参数
fprintf('\n[1/8] 加载XB4机械臂参数...\n');
d1=0.342; a1=0.040; a2=0.275; a3=0.025; d4=0.280; dt=0.073; d3=0;
m = [0.167, 1, 0.5, 0.333, 0.25, 0.2];
mc = [
    0,      0,      0.2;
    0.1291, 0,      3.3117;
    1.6484, 0,      0.8748;
    0.3200, 0.2324, 0.7083;
    0.4574, 0,      0.6427;
    0.3200, -0.0513, 0.6417
];
Ic_diag = [
    0,       0,       1.3676;
    8.8194,  6.0549,  0.9569;
    0.0332,  1.8442,  1.0560;
    0.1448,  0.0015,  0.0822;
    0,       0.0121,  0.0299;
    0.0134,  0,       0.0051
];
Ic = cell(6,1);
for i=1:6; Ic{i} = diag(Ic_diag(i,:)); end
g = 9.80200;
Ia = zeros(6,1); fv = zeros(6,1); fc = zeros(6,1);
offset2 = -pi/2;
fprintf('    参数加载完成。\n');

%% 3. 期望轨迹
fprintf('[2/8] 生成期望轨迹...\n');
T_end = 10;
dt = 0.001;
t = (0:dt:T_end)';
n_steps = length(t);

% 实验一: 关节1+6正弦
Amp1=0.5; Freq1=1;
Amp6=0.3; Freq6=2;
q_des1  = zeros(n_steps,6);
qd_des1 = zeros(n_steps,6);
qdd_des1= zeros(n_steps,6);
q_des1(:,1)  = Amp1*sin(Freq1*t); q_des1(:,6)  = Amp6*sin(Freq6*t);
qd_des1(:,1) = Amp1*Freq1*cos(Freq1*t); qd_des1(:,6) = Amp6*Freq6*cos(Freq6*t);
qdd_des1(:,1)= -Amp1*Freq1^2*sin(Freq1*t); qdd_des1(:,6)= -Amp6*Freq6^2*sin(Freq6*t);

% 实验二: 关节2+4+5多频
Amp2=0.4; F2a=0.5; F2b=1.0; F2c=1.5;
Amp4=0.3; Freq4=0.5;
Amp5=0.2; Freq5=0.8;
q_des2  = zeros(n_steps,6);
qd_des2 = zeros(n_steps,6);
qdd_des2= zeros(n_steps,6);
q_des2(:,2)  = Amp2*(sin(F2a*t)+0.5*sin(F2b*t)+0.25*sin(F2c*t));
q_des2(:,4)  = Amp4*sin(Freq4*t);
q_des2(:,5)  = Amp5*sin(Freq5*t);
qd_des2(:,2) = Amp2*(F2a*cos(F2a*t)+0.5*F2b*cos(F2b*t)+0.25*F2c*cos(F2c*t));
qd_des2(:,4) = Amp4*Freq4*cos(Freq4*t);
qd_des2(:,5) = Amp5*Freq5*cos(Freq5*t);
qdd_des2(:,2)= -Amp2*(F2a^2*sin(F2a*t)+0.5*F2b^2*sin(F2b*t)+0.25*F2c^2*sin(F2c*t));
qdd_des2(:,4)= -Amp4*Freq4^2*sin(Freq4*t);
qdd_des2(:,5)= -Amp5*Freq5^2*sin(Freq5*t);
fprintf('    轨迹生成完成，共%d个时间点。\n', n_steps);

%% 4. PID参数 (适当降低保证稳定)
fprintf('[3/8] 设置PID参数...\n');
Kp = [15, 15, 10, 8, 5, 4];
Kd = [6,  6,  4, 3, 2, 1.5];
fprintf('    Kp = [%.1f %.1f %.1f %.1f %.1f %.1f]\n', Kp);
fprintf('    Kd = [%.1f %.1f %.1f %.1f %.1f %.1f]\n', Kd);

%% 5. 仿真 (使用ode15s处理刚性问题)
fprintf('[4/8] 运行仿真...\n');

% ode15s更适合处理6-DOF机械臂这类刚性问题
opts = odeset('RelTol',1e-5,'AbsTol',1e-7,'MaxStep',0.05);
x0 = zeros(12,1);

% 实验一: 纯PID
fprintf('  [实验一] 纯PID控制...\n');
tic;
[~, ~, t1_p, x1_p] = run_one_sim(t, q_des1, qd_des1, qdd_des1, Kp, Kd, 0, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
fprintf('    完成 (%.2fs, %d个数据点)\n', toc, length(t1_p));

% 实验一: PID+前馈
fprintf('  [实验一] PID+前馈控制...\n');
tic;
[~, ~, t1_f, x1_f] = run_one_sim(t, q_des1, qd_des1, qdd_des1, Kp, Kd, 1, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
fprintf('    完成 (%.2fs, %d个数据点)\n', toc, length(t1_f));

% 实验二: 纯PID
fprintf('  [实验二] 纯PID控制...\n');
tic;
[~, ~, t2_p, x2_p] = run_one_sim(t, q_des2, qd_des2, qdd_des2, Kp, Kd, 0, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
fprintf('    完成 (%.2fs, %d个数据点)\n', toc, length(t2_p));

% 实验二: PID+前馈
fprintf('  [实验二] PID+前馈控制...\n');
tic;
[~, ~, t2_f, x2_f] = run_one_sim(t, q_des2, qd_des2, qdd_des2, Kp, Kd, 1, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
fprintf('    完成 (%.2fs, %d个数据点)\n', toc, length(t2_f));

%% 6. 提取结果并插值到统一时间网格
fprintf('[5/8] 提取仿真结果...\n');

% 所有结果插值到原始时间网格 t，保证维度一致
% interp1返回 (length(t), 6)，转置为 (6, length(t))
q1p  = interp1(t1_p, x1_p(:,1:6), t); q1p(isnan(q1p)) = 0; q1p  = q1p';
qd1p = interp1(t1_p, x1_p(:,7:12), t); qd1p(isnan(qd1p)) = 0; qd1p = qd1p';
q1f  = interp1(t1_f, x1_f(:,1:6), t);  q1f(isnan(q1f))  = 0; q1f  = q1f';
qd1f = interp1(t1_f, x1_f(:,7:12), t); qd1f(isnan(qd1f)) = 0; qd1f = qd1f';
q2p  = interp1(t2_p, x2_p(:,1:6), t);  q2p(isnan(q2p))  = 0; q2p  = q2p';
qd2p = interp1(t2_p, x2_p(:,7:12), t); qd2p(isnan(qd2p)) = 0; qd2p = qd2p';
q2f  = interp1(t2_f, x2_f(:,1:6), t);  q2f(isnan(q2f))  = 0; q2f  = q2f';
qd2f = interp1(t2_f, x2_f(:,7:12), t); qd2f(isnan(qd2f)) = 0; qd2f = qd2f';

% 跟踪误差 (行: 关节, 列: 时间)
err1p = q_des1' - q1p;
err1f = q_des1' - q1f;
err2p = q_des2' - q2p;
err2f = q_des2' - q2f;

fprintf('[6/8] 生成图表...\n');
savedir = '结果图';
LW = 1.5;
FS = 11;

% ===== 图11: 关节1和6的位置/速度跟踪 =====
figure('Name','图11','Position',[100,100,1000,700],'Color','w');
ha = axes('Visible','off'); title(ha,'图11 实验一 关节1和6运动轨迹和速度','FontSize',13,'FontWeight','bold');
for ji=1:2
    j = [1,6];
    subplot(2,2,ji);
    plot(t, q_des1(:,j(ji)), 'b-', t, q1p(j(ji),:), 'r--', t, q1f(j(ji),:), 'g-.', 'LineWidth',LW);
    xlabel('时间 (s)'); ylabel(['q_' num2str(j(ji)) ' (rad)']);
    title(['关节' num2str(j(ji)) '位置跟踪']); grid on;
    if ji==1; legend({'期望','PID','PID+前馈'},'Location','best','FontSize',FS); end
    subplot(2,2,ji+2);
    plot(t, qd_des1(:,j(ji)), 'b-', t, qd1p(j(ji),:), 'r--', t, qd1f(j(ji),:), 'g-.', 'LineWidth',LW);
    xlabel('时间 (s)'); ylabel(['qd_' num2str(j(ji)) ' (rad/s)']);
    title(['关节' num2str(j(ji)) '速度跟踪']); grid on;
end
saveas(gcf, fullfile(savedir,'图11_关节1和6运动轨迹速度.png'));
fprintf('    已保存: 图11_关节1和6运动轨迹速度.png\n');

% ===== 图12: 各关节力矩 =====
figure('Name','图12','Position',[100,100,1000,700],'Color','w');
ha = axes('Visible','off'); title(ha,'图12 实验一 各关节力矩 (PID vs PID+前馈)','FontSize',13,'FontWeight','bold');
torque1p = zeros(6,n_steps);
torque1f = zeros(6,n_steps);
for k=1:n_steps
    qdd_approx  = gradient(q1p(:,k),  t(1));
    qdd_approx2 = gradient(q1f(:,k),   t(1));
    torque1p(:,k) = compute_torque(q1p(:,k),  qd1p(:,k),  qdd_approx,  d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    torque1f(:,k) = compute_torque(q1f(:,k),  qd1f(:,k),  qdd_approx2, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
end
for j=1:6
    subplot(2,3,j);
    plot(t, torque1p(j,:)', 'r-', t, torque1f(j,:)', 'g--', 'LineWidth',LW);
    xlabel('时间 (s)'); ylabel(['T_' num2str(j) ' (Nm)']);
    title(['关节' num2str(j) '力矩']); grid on;
    if j==1; legend({'PID','PID+前馈'},'Location','best','FontSize',FS); end
end
saveas(gcf, fullfile(savedir,'图12_PID各关节力矩.png'));
fprintf('    已保存: 图12_PID各关节力矩.png\n');

% ===== 图13: 误差对比 =====
figure('Name','图13','Position',[100,100,900,600],'Color','w');
ha = axes('Visible','off'); title(ha,'图13 实验一 关节跟踪误差对比 (PID vs PID+前馈)','FontSize',13,'FontWeight','bold');
for idx=1:2
    j=[1,6];
    subplot(2,1,idx);
    plot(t, err1p(j(idx),:)', 'r-', t, err1f(j(idx),:)', 'g-', 'LineWidth',LW);
    xlabel('时间 (s)'); ylabel(['e_' num2str(j(idx)) ' (rad)']);
    title(['关节' num2str(j(idx)) '跟踪误差']); grid on;
    legend({'PID误差','PID+前馈误差'},'Location','best','FontSize',FS);
end
saveas(gcf, fullfile(savedir,'图13_PID_vs_PID前馈误差对比.png'));
fprintf('    已保存: 图13_PID_vs_PID前馈误差对比.png\n');

% ===== 图14: 实验二误差对比 =====
figure('Name','图14','Position',[100,100,900,600],'Color','w');
ha = axes('Visible','off'); title(ha,'图14 实验二 关节跟踪误差对比 (PID vs PID+前馈)','FontSize',13,'FontWeight','bold');
for idx=1:2
    j=[1,6];
    subplot(2,1,idx);
    plot(t, err2p(j(idx),:)', 'r-', t, err2f(j(idx),:)', 'g-', 'LineWidth',LW);
    xlabel('时间 (s)'); ylabel(['e_' num2str(j(idx)) ' (rad)']);
    title(['关节' num2str(j(idx)) '跟踪误差']); grid on;
    legend({'PID误差','PID+前馈误差'},'Location','best','FontSize',FS);
end
saveas(gcf, fullfile(savedir,'图14_实验二_误差对比.png'));
fprintf('    已保存: 图14_实验二_误差对比.png\n');

% ===== 图15: 实验二各关节响应 =====
figure('Name','图15','Position',[100,100,1000,700],'Color','w');
ha = axes('Visible','off'); title(ha,'图15 实验二 各关节响应对比','FontSize',13,'FontWeight','bold');
for j=1:6
    subplot(2,3,j);
    plot(t, q_des2(:,j), 'b-', t, q2p(j,:)', 'r--', t, q2f(j,:)', 'g-.', 'LineWidth',LW);
    xlabel('时间 (s)'); ylabel(['q_' num2str(j) ' (rad)']);
    title(['关节' num2str(j)]); grid on;
    if j==1; legend({'期望','PID','PID+前馈'},'Location','best','FontSize',FS); end
end
saveas(gcf, fullfile(savedir,'图15_实验二_各关节响应对比.png'));
fprintf('    已保存: 图15_实验二_各关节响应对比.png\n');
close all;

%% 7. 误差统计
fprintf('[7/8] 打印误差统计...\n');
fprintf('\n========== 跟踪误差统计 ==========\n');
fprintf('实验一 - 纯PID:\n');
for j=1:6
    fprintf('  关节%d: RMS=%.5f rad, Max=%.5f rad\n', j, sqrt(mean(err1p(j,:).^2)), max(abs(err1p(j,:))));
end
fprintf('实验一 - PID+前馈:\n');
for j=1:6
    fprintf('  关节%d: RMS=%.5f rad, Max=%.5f rad\n', j, sqrt(mean(err1f(j,:).^2)), max(abs(err1f(j,:))));
end
fprintf('实验二 - 纯PID:\n');
for j=1:6
    fprintf('  关节%d: RMS=%.5f rad, Max=%.5f rad\n', j, sqrt(mean(err2p(j,:).^2)), max(abs(err2p(j,:))));
end
fprintf('实验二 - PID+前馈:\n');
for j=1:6
    fprintf('  关节%d: RMS=%.5f rad, Max=%.5f rad\n', j, sqrt(mean(err2f(j,:).^2)), max(abs(err2f(j,:))));
end
fprintf('====================================\n');

fprintf('[8/8] 完成！\n');
fprintf('\n所有图片已保存到「结果图」文件夹。\n');
fprintf('请将图片复制到实验报告「前馈控制实验报告.docx」中。\n');

end  % ========== 主函数结束 ==========

%% ========== 以下是局部函数 ==========

% ---- 运行一次仿真的包装函数 ----
function [te, xe, tout, xout] = run_one_sim(t, q_des, qd_des, qdd_des, Kp, Kd, use_ff, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc)
    opts = odeset('RelTol',1e-5,'AbsTol',1e-7,'MaxStep',0.05,'OutputFcn',@outfun);
    x0 = zeros(12,1);
    if use_ff == 0
        [te, xe] = ode15s(@(tt,xx) dynamics_pid(tt,xx,t,q_des,qd_des,Kp,Kd,d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc), t, x0, opts);
    else
        [te, xe] = ode15s(@(tt,xx) dynamics_ff(tt,xx,t,q_des,qd_des,qdd_des,Kp,Kd,d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc), t, x0, opts);
    end
    tout = te; xout = xe;
end

% ---- OutputFcn: 监控仿真状态 ----
function status = outfun(t, x, flag)
    status = 0;
end

% ---- 纯PID动力学 (用于ode15s) ----
function dx = dynamics_pid(tt, xx, t, q_des, qd_des, Kp, Kd, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc)
    q = xx(1:6); qd = xx(7:12);
    k = min(round(tt/dt)+1, length(t));
    q_d = q_des(k,:)'; qd_d = qd_des(k,:)';
    e = q_d - q; ed = qd_d - qd;
    tau = Kp'.*e + Kd'.*ed;
    % 力矩限幅
    tau = max(min(tau, 200), -200);
    qdd = compute_qdd(q, qd, tau, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    dx = [qd; qdd];
end

% ---- PID+前馈动力学 (用于ode15s) ----
function dx = dynamics_ff(tt, xx, t, q_des, qd_des, qdd_des, Kp, Kd, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc)
    q = xx(1:6); qd = xx(7:12);
    k = min(round(tt/dt)+1, length(t));
    q_d = q_des(k,:)'; qd_d = qd_des(k,:)'; qdd_d = qdd_des(k,:)';
    e = q_d - q; ed = qd_d - qd;
    tau_ff = compute_torque(q_d, qd_d, qdd_d, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    tau_fb = Kp'.*e + Kd'.*ed;
    tau = tau_ff + tau_fb;
    % 力矩限幅
    tau = max(min(tau, 200), -200);
    qdd = compute_qdd(q, qd, tau, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    dx = [qd; qdd];
end

% ---- 计算前向动力学 qdd = M^{-1}(tau - f) ----
function qdd = compute_qdd(q, qd, tau, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc)
    eps2 = 1e-5;
    T0 = compute_torque(q, qd, zeros(6,1), d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    T1 = compute_torque(q, qd, [eps2;0;0;0;0;0], d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    T2 = compute_torque(q, qd, [0;eps2;0;0;0;0], d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    T3 = compute_torque(q, qd, [0;0;eps2;0;0;0], d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    T4 = compute_torque(q, qd, [0;0;0;eps2;0;0], d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    T5 = compute_torque(q, qd, [0;0;0;0;eps2;0], d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    T6 = compute_torque(q, qd, [0;0;0;0;0;eps2], d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc);
    M_cols = [(T1-T0)/eps2, (T2-T0)/eps2, (T3-T0)/eps2, (T4-T0)/eps2, (T5-T0)/eps2, (T6-T0)/eps2];
    qdd = M_cols \ (tau - T0);
end

% ---- 逆动力学: 基于Newton-Euler算法 ----
function T = compute_torque(q, qd, qdd, d1,a1,a2,a3,d4,dt,offset2,g,m,mc,Ic,Ia,fv,fc)
    function Tmat = dhT(theta, d, a, alpha)
        ct=cos(theta); st=sin(theta); ca=cos(alpha); sa=sin(alpha);
        Tmat=[ct,-st*ca, st*sa, a*ct;
              st, ct*ca,-ct*sa, a*st;
               0,    sa,    ca,     d;
               0,     0,     0,     1];
    end

    % 各连杆D-H变换矩阵
    T01 = dhT(q(1),         d1,  a1, 0);
    T12 = dhT(q(2)+offset2,  0,   a2, -pi/2);
    T23 = dhT(q(3),          0,   a3, 0);
    T34 = dhT(q(4),         d4,   0,  -pi/2);
    T45 = dhT(q(5),          0,   0,   pi/2);
    T56 = dhT(q(6),         dt,   0,  -pi/2);

    T02 = T01*T12; T03 = T02*T23; T04 = T03*T34;
    T05 = T04*T45; T06 = T05*T56;

    % 关节位置向量
    P01=T01(1:3,4); P12=T12(1:3,4); P23=T23(1:3,4);
    P34=T34(1:3,4); P45=T45(1:3,4); P56=T56(1:3,4);

    % 质心位置 (基坐标系)
    Ttabs = {T01,T02,T03,T04,T05,T06};
    Pc = zeros(3,6);
    for i=1:6
        Ti = Ttabs{i};
        Pc(:,i) = Ti(1:3,1:3)*mc(i,:)' + Ti(1:3,4);
    end

    % 质心相对位置
    PPc{1} = Pc(:,1)-P01;
    PPc{2} = Pc(:,2)-T02(1:3,4);
    PPc{3} = Pc(:,3)-T03(1:3,4);
    PPc{4} = Pc(:,4)-T04(1:3,4);
    PPc{5} = Pc(:,5)-T05(1:3,4);
    PPc{6} = Pc(:,6)-T06(1:3,4);

    % 初始条件
    w0=[0;0;0]; wd0=[0;0;0]; v0=[0;0;0]; vd0=[0;g;0];
    z=[0;0;1];

    % ===== 正向递归 =====
    w=zeros(3,7); wd=zeros(3,7); v=zeros(3,7); vd_c=zeros(3,6);
    w(:,1)=w0; wd(:,1)=wd0; v(:,1)=v0;

    % Link 1
    R01=T01(1:3,1:3);
    w(:,2)=R01'*(w(:,1)+z*qd(1));
    wd(:,2)=R01'*(wd(:,1)+cross(w(:,1),z*qd(1))+z*qdd(1));
    vd_c(:,1)=cross(wd(:,2),PPc{1})+cross(w(:,2),cross(w(:,2),PPc{1})) ...
              +R01'*(cross(wd(:,1),P01)+cross(w(:,1),cross(w(:,1),P01))+vd0);
    v(:,2)=v(:,1)+cross(w(:,1),P01);

    % Link 2
    R12=T12(1:3,1:3);
    w(:,3)=R12'*(w(:,2)+z*qd(2));
    wd(:,3)=R12'*(wd(:,2)+cross(w(:,2),z*qd(2))+z*qdd(2));
    vd_c(:,2)=cross(wd(:,3),PPc{2})+cross(w(:,3),cross(w(:,3),PPc{2})) ...
              +R12'*(cross(wd(:,2),P12)+cross(w(:,2),cross(w(:,2),P12))+v(:,2));
    v(:,3)=v(:,2)+cross(w(:,2),P12);

    % Link 3
    R23=T23(1:3,1:3);
    w(:,4)=R23'*(w(:,3)+z*qd(3));
    wd(:,4)=R23'*(wd(:,3)+cross(w(:,3),z*qd(3))+z*qdd(3));
    vd_c(:,3)=cross(wd(:,4),PPc{3})+cross(w(:,4),cross(w(:,4),PPc{3})) ...
              +R23'*(cross(wd(:,3),P23)+cross(w(:,3),cross(w(:,3),P23))+v(:,3));
    v(:,4)=v(:,3)+cross(w(:,3),P23);

    % Link 4
    R34=T34(1:3,1:3);
    w(:,5)=R34'*(w(:,4)+z*qd(4));
    wd(:,5)=R34'*(wd(:,4)+cross(w(:,4),z*qd(4))+z*qdd(4));
    vd_c(:,4)=cross(wd(:,5),PPc{4})+cross(w(:,5),cross(w(:,5),PPc{4})) ...
              +R34'*(cross(wd(:,4),P34)+cross(w(:,4),cross(w(:,4),P34))+v(:,4));
    v(:,5)=v(:,4)+cross(w(:,4),P34);

    % Link 5
    R45=T45(1:3,1:3);
    w(:,6)=R45'*(w(:,5)+z*qd(5));
    wd(:,6)=R45'*(wd(:,5)+cross(w(:,5),z*qd(5))+z*qdd(5));
    vd_c(:,5)=cross(wd(:,6),PPc{5})+cross(w(:,6),cross(w(:,6),PPc{5})) ...
              +R45'*(cross(wd(:,5),P45)+cross(w(:,5),cross(w(:,5),P45))+v(:,5));
    v(:,6)=v(:,5)+cross(w(:,5),P45);

    % Link 6
    R56=T56(1:3,1:3);
    w(:,7)=R56'*(w(:,6)+z*qd(6));
    wd(:,7)=R56'*(wd(:,6)+cross(w(:,6),z*qd(6))+z*qdd(6));
    vd_c(:,6)=cross(wd(:,7),PPc{6})+cross(w(:,7),cross(w(:,7),PPc{6})) ...
              +R56'*(cross(wd(:,6),P56)+cross(w(:,6),cross(w(:,6),P56))+v(:,6));
    v(:,7)=v(:,6)+cross(w(:,6),P56);

    % ===== 反向递归 =====
    f=zeros(3,7); n=zeros(3,7); f(:,7)=[0;0;0]; n(:,7)=[0;0;0];
    Rtabs = {R01,R12,R23,R34,R45,R56};
    Ttabs2 = {T01,T12,T23,T34,T45,T56};

    for i=6:-1:1
        Ri = Rtabs{i};
        Fi = m(i)*vd_c(:,i);
        Ni = Ic{i}*wd(:,i+1) + cross(w(:,i+1), Ic{i}*w(:,i+1));
        f(:,i) = Ri*f(:,i+1) + Fi;
        n(:,i) = Ni + cross(PPc{i}, Fi) + Ri*n(:,i+1);
    end

    % 提取关节力矩
    T=zeros(6,1);
    for i=1:6
        Ri_prev = Ttabs2{i}(1:3,1:3);
        zi = Ri_prev' * z;
        T(i) = n(:,i)'*zi + Ia(i)*qdd(i) + fv(i)*qd(i) + fc(i)*sign(qd(i)+1e-10);
    end
end
