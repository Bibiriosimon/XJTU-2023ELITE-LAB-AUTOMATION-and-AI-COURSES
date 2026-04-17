function r = reference_tanks(t)
% 两个液位的参考信号（分段阶跃）

if t < 20
    r = [6.0; 5.0];
elseif t < 60
    r = [8.0; 6.5];
elseif t < 90
    r = [10.0; 7.5];
else
    r = [9.0; 6.0];
end
end