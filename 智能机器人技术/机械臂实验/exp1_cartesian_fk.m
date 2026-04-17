clc; clear; close all;

%% 1. 载入 PUMA560 模型
mdl_puma560

%% 2. 设定起始和终止关节姿态（工具箱自带，可达性较稳）
q_start = qz;
q_end   = qr;

%% 3. 由关节姿态计算起点和终点的末端位姿
T_start = p560.fkine(q_start);
T_end   = p560.fkine(q_end);

%% 4. 在笛卡尔空间进行轨迹规划
n = 50;
Ts = ctraj(T_start, T_end, n);

%% 5. 对整条轨迹做逆运动学，得到关节轨迹
% 注意：ikine6s 对轨迹输入时通常直接返回 n×6
q_traj = p560.ikine6s(Ts);

%% 6. 提取规划轨迹中的末端位置，并用正运动学进行验证
xyz_plan = zeros(n, 3);
xyz_fk   = zeros(n, 3);

for i = 1:n
    % ---------- 读取规划轨迹点 ----------
    if isa(Ts, 'SE3')
        % 如果 Ts 是 SE3 轨迹对象
        xyz_plan(i, :) = transl(Ts(i));
    else
        % 如果 Ts 是 4x4xn 数值数组
        xyz_plan(i, :) = Ts(1:3, 4, i)';
    end

    % ---------- 正运动学验证 ----------
    T_now = p560.fkine(q_traj(i, :));
    xyz_fk(i, :) = transl(T_now);
end

%% 7. 计算位置误差
err = sqrt(sum((xyz_plan - xyz_fk).^2, 2));

%% 8. 机械臂运动动画
figure;
p560.plot(q_traj);
title('Cartesian Trajectory Execution');

%% 9. 绘制规划轨迹与正运动学验证轨迹对比
figure;
plot3(xyz_plan(:,1), xyz_plan(:,2), xyz_plan(:,3), 'r--', 'LineWidth', 2); hold on;
plot3(xyz_fk(:,1),   xyz_fk(:,2),   xyz_fk(:,3),   'b-',  'LineWidth', 1.5);
grid on; axis equal;
xlabel('X');
ylabel('Y');
zlabel('Z');
legend('Planned trajectory', 'FK verified trajectory');
title('Cartesian trajectory vs FK verification');

%% 10. 绘制位置误差曲线
figure;
plot(err, 'LineWidth', 1.5);
grid on;
xlabel('Point index');
ylabel('Position error (m)');
title('FK verification error');

%% 11. 输出最大误差
disp('最大位置误差（m）：');
disp(max(err));
figure;
plot(xyz_plan(:,1), 'r', 'LineWidth', 1.2); hold on;
plot(xyz_plan(:,2), 'g', 'LineWidth', 1.2);
plot(xyz_plan(:,3), 'b', 'LineWidth', 1.2);
grid on;
xlabel('Point index');
ylabel('Position (m)');
legend('x','y','z');
title('End-effector position components');