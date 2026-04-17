function fis = build_tank_fis(nameStr)
% 构建一个二维 Mamdani 模糊控制器
% 输入: E, DE
% 输出: DU
%
% 注意：
% - 这里的 E, DE, DU 都是在归一化论域 [-3, 3] 上工作的
% - 实际量通过 Ke, Kde, Ku 做缩放

fis = mamfis('Name', nameStr, ...
    'AndMethod', 'min', ...
    'OrMethod', 'max', ...
    'ImplicationMethod', 'min', ...
    'AggregationMethod', 'max', ...
    'DefuzzificationMethod', 'centroid');

% 输入输出变量
fis = addInput(fis, [-3 3], 'Name', 'E');
fis = addInput(fis, [-3 3], 'Name', 'DE');
fis = addOutput(fis, [-3 3], 'Name', 'DU');

% 7个语言变量：NB NM NS ZO PS PM PB
labels = {'NB','NM','NS','ZO','PS','PM','PB'};

% 给 E 添加隶属函数
for i = 1:7
    fis = addMF(fis, 'E', 'trimf', mf_params(i), 'Name', labels{i});
end

% 给 DE 添加隶属函数
for i = 1:7
    fis = addMF(fis, 'DE', 'trimf', mf_params(i), 'Name', labels{i});
end

% 给 DU 添加隶属函数
for i = 1:7
    fis = addMF(fis, 'DU', 'trimf', mf_params(i), 'Name', labels{i});
end

% 规则表（行：E，列：DE，值：DU）
% 1..7 分别对应 NB NM NS ZO PS PM PB
ruleIdx = [ ...
    1 1 2 2 3 4 4;   % E = NB
    1 2 2 3 4 5 5;   % E = NM
    2 2 3 4 5 6 6;   % E = NS
    2 3 4 4 4 5 6;   % E = ZO
    3 4 5 6 6 6 7;   % E = PS
    4 5 6 6 7 7 7;   % E = PM
    4 4 6 6 7 7 7];  % E = PB

% 转成 rule list
ruleList = zeros(49, 5);
idx = 1;
for i = 1:7
    for j = 1:7
        ruleList(idx, :) = [i, j, ruleIdx(i,j), 1, 1];
        idx = idx + 1;
    end
end

fis = addRule(fis, ruleList);
end

function p = mf_params(i)
% 7个三角形隶属函数参数
% NB [-4 -3 -2]
% NM [-3 -2 -1]
% NS [-2 -1  0]
% ZO [-1  0  1]
% PS [ 0  1  2]
% PM [ 1  2  3]
% PB [ 2  3  4]
switch i
    case 1, p = [-4 -3 -2];
    case 2, p = [-3 -2 -1];
    case 3, p = [-2 -1  0];
    case 4, p = [-1  0  1];
    case 5, p = [ 0  1  2];
    case 6, p = [ 1  2  3];
    case 7, p = [ 2  3  4];
end
end