function dh = tank_dynamics(h, u, p)
% 非线性耦合双容水箱动力学
%
% h = [h1; h2]
% u = [u1; u2]

h1 = max(h(1), 0);
h2 = max(h(2), 0);

u1 = min(max(u(1), p.u_min), p.u_max);
u2 = min(max(u(2), p.u_min), p.u_max);

% 进水流量
q1 = p.k1 * u1;
q2 = p.k2 * u2;

% 各箱出流（非线性）
qout1 = p.c1 * sqrt(h1);
qout2 = p.c2 * sqrt(h2);

% 两箱耦合流量
q12 = p.c12 * sign(h1 - h2) * sqrt(abs(h1 - h2));

% 动态方程
dh1 = (q1 - qout1 - q12) / p.A1;
dh2 = (q2 - qout2 + q12) / p.A2;

dh = [dh1; dh2];
end