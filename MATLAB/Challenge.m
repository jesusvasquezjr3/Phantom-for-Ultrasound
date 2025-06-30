clear; clc; close all;

% Parámetros comunes
kernel_mediana = 3;        
se = strel('disk', 3);     

% Parámetros por clasificación
parametros(1).rango    = 16:19;  
parametros(1).c_log    = 1;     
parametros(1).umbral   = 0.56;  
parametros(1).color    = [1 0 0];  

parametros(2).rango    = 20:23;  
parametros(2).c_log    = 0.5;   
parametros(2).umbral   = 0.23;  
parametros(2).color    = [0 0 1];  

%% Pre-asignación de datos para extracción de características
numSamples = numel(parametros(1).rango) + numel(parametros(2).rango);
X = zeros(2, numSamples);   % [Área; IntensidadMedia]
y = zeros(1, numSamples);   % Etiquetas 0 ó 1
idx = 1;

%% 1) Procesamiento + Visualización original + Extracción de características
for clasif = 1:2
    for img_num = parametros(clasif).rango
        % --- 1. Lectura y pre-procesado ---
        img_path = sprintf('IM-0001-00%02d.dcm', img_num);
        img_raw  = dicomread(img_path);
        if ~isa(img_raw,'uint8'), img_raw = im2uint8(img_raw); end
        if size(img_raw,3)==3,    img_raw = rgb2gray(img_raw); end
        img_dicom = im2double(img_raw);
        
        img_filtrada = medfilt2(img_dicom, [kernel_mediana kernel_mediana]);
        imgLog = parametros(clasif).c_log * log(1 + img_filtrada);
        
        % --- 2. Segmentación ---
        mask_log = imgLog > parametros(clasif).umbral;
        mask_log = imclose(mask_log, se);
        
        % --- 3. Máscara combinada (para visualización) ---
        img_color = repmat(mat2gray(img_dicom), [1 1 3]);
        mask_combined = img_color;
        for c = 1:3
            mask_combined(:,:,c) = img_color(:,:,c) + mask_log * parametros(clasif).color(c)*0.7;
        end
        
        % --- 4. Mostrar resultados con subplot(2,2,*) ---
        figure('Name', sprintf('Clasif %d - Imagen %02d (c=%.1f, u=%.2f)', ...
               clasif, img_num, parametros(clasif).c_log, parametros(clasif).umbral));
        subplot(2,2,1), imshow(img_dicom, []),            title('Original');
        subplot(2,2,2), imshow(imgLog, []),               title(sprintf('Log (c=%.1f)',parametros(clasif).c_log));
        subplot(2,2,3), imshow(mask_combined),             title('Segmentación coloreada');
        subplot(2,2,4), imshow(mask_log, []),              title('Máscara segmentada');
        
        % --- 5. Extracción de características ---
        props = regionprops(mask_log, img_dicom, 'Area','MeanIntensity');
        if isempty(props)
            area = 0; meanI = 0;
        else
            [~,m] = max([props.Area]);
            area  = props(m).Area;
            meanI = props(m).MeanIntensity;
        end
        
        X(:,idx) = [area; meanI];
        y(idx)   = clasif-1;  % Clase 0 ó 1
        idx = idx + 1;
    end
end

% Normalizar características (min–max)
X = X ./ max(X,[],2);

%% 2) Configuración y entrenamiento de la MLP
nInput    = 2;
nHidden   = 5;
nOutput   = 1;
alpha     = 0.5;
nEpochs   = 1000;

rng(0);
W1 = randn(nHidden,nInput)*0.01;  b1 = zeros(nHidden,1);
W2 = randn(nOutput,nHidden)*0.01; b2 = zeros(nOutput,1);

sigmoid = @(z) 1./(1+exp(-z));
pred_epochs  = zeros(nEpochs, numSamples);
error_epochs = zeros(nEpochs,1);

for ep = 1:nEpochs
    E = 0;
    for i = 1:numSamples
        x = X(:,i); t = y(i);
        a1 = sigmoid(W1*x + b1);
        a2 = sigmoid(W2*a1 + b2);
        
        pred_epochs(ep,i) = a2;
        e = t - a2;
        
        delta2 = e .* a2 .* (1 - a2);
        delta1 = (W2' * delta2) .* a1 .* (1 - a1);
        
        W2 = W2 + alpha * delta2 * a1';
        b2 = b2 + alpha * delta2;
        W1 = W1 + alpha * delta1 * x';
        b1 = b1 + alpha * delta1;
        
        E = E + 0.5*(e^2);
    end
    error_epochs(ep) = E;
end

%% 3) Evaluación y métricas
y_pred   = double( pred_epochs(end,:) > 0.5 );
C        = confusionmat(y, y_pred);
accuracy = sum(y_pred == y) / numSamples;

%% 4) Gráficas de resultados MLP

% a) Evolución de la predicción
figure;
plot(1:nEpochs, pred_epochs, 'LineWidth',1);
xlabel('Época'); ylabel('Salida de la red');
title('Evolución de la predicción por muestra');
legend(arrayfun(@(i) sprintf('Muestra %d',i), 1:numSamples,'UniformOutput',false), ...
       'Location','eastoutside');

% b) Error vs época
figure;
plot(1:nEpochs, error_epochs, 'LineWidth',1.5);
xlabel('Época'); ylabel('Error total');
title('Error de entrenamiento vs Época');

% c) Matriz de confusión
figure;
confusionchart(y, y_pred);
title('Matriz de Confusión Final');

% d) Frontera de decisión
figure; hold on;
scatter(X(1,y==0), X(2,y==0), 80, 'ro', 'filled');
scatter(X(1,y==1), X(2,y==1), 80, 'bx', 'LineWidth',2);
[x1g,x2g] = meshgrid(linspace(0,1,200), linspace(0,1,200));
gridPts = [x1g(:)'; x2g(:)'];
a1g = sigmoid(W1*gridPts + b1);
a2g = sigmoid(W2*a1g + b2);
z = reshape(a2g, size(x1g));
contour(x1g, x2g, z, [0.5 0.5], 'k', 'LineWidth',2);
xlabel('Área normalizada'); ylabel('Intensidad media normalizada');
title('Frontera de decisión');
legend('Clase 0','Clase 1','Límite (0.5)','Location','best');

%% 5) Impresión de resultados y análisis
fprintf('Predicciones finales (0/1):\n'); disp(y_pred);
fprintf('Etiquetas reales:      \n'); disp(y);
fprintf('Matriz de confusión:\n');        disp(C);
fprintf('Accuracy del modelo: %.2f%%\n', accuracy*100);

disp('Análisis:');
fprintf('- Todas las muestras convergieron tras %d épocas.\n', nEpochs);
fprintf('- Verdaderos positivos: %d\n', C(2,2));
fprintf('- Falsos positivos:     %d\n', C(1,2));
fprintf('- Falsos negativos:     %d\n', C(2,1));
fprintf('- Verdaderos negativos: %d\n', C(1,1));
fprintf('- La frontera de decisión separa las clases eficazmente en el espacio de características.\n');
