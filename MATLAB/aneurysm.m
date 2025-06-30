function aneurysmAnalysis()
    % Interfaz para seleccionar archivo DICOM
    [filename, pathname] = uigetfile('*.dcm', 'Seleccione una imagen DICOM');
    if isequal(filename, 0)
        disp('Usuario canceló la selección');
        return;
    end
    fullpath = fullfile(pathname, filename);
    
    % Cargar imagen DICOM
    dicomInfo = dicominfo(fullpath);
    originalImage = dicomread(dicomInfo);
    
    % Asegurarse de que la imagen es 2D (eliminar dimensiones adicionales)
    if ndims(originalImage) > 2
        originalImage = squeeze(originalImage(:,:,1));
    end
    
    % Normalizar imagen para visualización
    normalizedImg = double(originalImage);
    normalizedImg = (normalizedImg - min(normalizedImg(:))) / (max(normalizedImg(:)) - min(normalizedImg(:)));
    
    % Crear figura con controles deslizantes
    fig = figure('Name', 'Análisis de Aneurisma', 'NumberTitle', 'off', 'Position', [100 100 1200 800]);
    
    % Parámetros ajustables con valores iniciales
    threshold = 0.7;
    minArea = 300;
    sigma = 2;
    fftScale = 1;
    filterRadius = 50;  % Nuevo parámetro para el filtro de FFT
    
    % Controles deslizantes
    uicontrol('Style', 'text', 'Position', [20 50 150 20], 'String', 'Umbral de segmentación:');
    uicontrol('Style', 'slider', 'Min', 0, 'Max', 1, 'Value', threshold, ...
              'Position', [20 30 150 20], 'Tag', 'threshold', ...
              'Callback', @updateDisplay);
    
    uicontrol('Style', 'text', 'Position', [20 100 150 20], 'String', 'Área mínima:');
    uicontrol('Style', 'slider', 'Min', 100, 'Max', 2000, 'Value', minArea, ...
              'Position', [20 80 150 20], 'Tag', 'minArea', ...
              'Callback', @updateDisplay);
    
    uicontrol('Style', 'text', 'Position', [20 150 150 20], 'String', 'Sigma para filtro Gauss:');
    uicontrol('Style', 'slider', 'Min', 0.5, 'Max', 5, 'Value', sigma, ...
              'Position', [20 130 150 20], 'Tag', 'sigma', ...
              'Callback', @updateDisplay);
    
    uicontrol('Style', 'text', 'Position', [20 200 150 20], 'String', 'Escala FFT:');
    uicontrol('Style', 'slider', 'Min', 0.1, 'Max', 5, 'Value', fftScale, ...
              'Position', [20 180 150 20], 'Tag', 'fftScale', ...
              'Callback', @updateDisplay);
    
    uicontrol('Style', 'text', 'Position', [20 250 150 20], 'String', 'Radio Filtro FFT:');
    uicontrol('Style', 'slider', 'Min', 10, 'Max', 100, 'Value', filterRadius, ...
              'Position', [20 230 150 20], 'Tag', 'filterRadius', ...
              'Callback', @updateDisplay);
    
    % Botón para guardar resultados
    uicontrol('Style', 'pushbutton', 'String', 'Guardar Resultados', ...
              'Position', [20 280 150 30], 'Callback', @saveResults);
    
    % Función para actualizar la visualización
    function updateDisplay(~, ~)
        % Obtener valores actuales de los controles
        threshold = get(findobj('Tag', 'threshold'), 'Value');
        minArea = round(get(findobj('Tag', 'minArea'), 'Value'));
        sigma = get(findobj('Tag', 'sigma'), 'Value');
        fftScale = get(findobj('Tag', 'fftScale'), 'Value');
        filterRadius = round(get(findobj('Tag', 'filterRadius'), 'Value'));
        
        % Procesamiento de la imagen
        processedImg = processImage(normalizedImg, threshold, minArea, sigma);
        [fftResult, filteredImg] = computeFFT(normalizedImg, fftScale, filterRadius);
        
        % Mostrar resultados
        showResults(originalImage, processedImg, fftResult, filteredImg, threshold, minArea, sigma);
    end
    
    % Función para procesar la imagen
    function processedImg = processImage(img, threshold, minArea, sigma)
        % Aplicar filtro Gaussiano para suavizar
        filteredImg = imgaussfilt(img, sigma);
        
        % Binarización adaptativa
        binaryImg = imbinarize(filteredImg, threshold);
        
        % Eliminar pequeños objetos
        binaryImg = bwareaopen(binaryImg, minArea);
        
        % Rellenar huecos
        binaryImg = imfill(binaryImg, 'holes');
        
        % Etiquetar componentes conectados (asegurarse que es 2D)
        labeledImg = bwlabel(binaryImg);
        
        % Calcular propiedades de regiones
        stats = regionprops(labeledImg, 'Area', 'Centroid', 'Eccentricity');
        
        % Identificar aneurisma (región más excéntrica)
        if numel(stats) >= 2
            eccentricities = [stats.Eccentricity];
            [~, idx] = max(eccentricities);
            
            % Crear máscara para aneurisma (rojo) y arteria sana (verde)
            aneurysmMask = labeledImg == idx;
            arteryMask = labeledImg ~= idx & labeledImg ~= 0;
            
            % Crear imagen RGB para visualización
            processedImg = cat(3, aneurysmMask, arteryMask, zeros(size(aneurysmMask)));
        else
            % Si no se detectan suficientes regiones
            processedImg = cat(3, zeros(size(img)), zeros(size(img)), zeros(size(img)));
        end
    end
    
    % Función para calcular FFT
    function [fftResult, filteredImg] = computeFFT(img, scaleFactor, radius)
        % Asegurarse que la imagen es 2D
        if ndims(img) > 2
            img = img(:,:,1);
        end
        
        % Aplicar FFT 2D
        fft2Img = fft2(img);
        
        % Desplazar frecuencias cero al centro
        fftShifted = fftshift(fft2Img);
        
        % Calcular magnitud logarítmica
        magnitude = log(1 + abs(fftShifted));
        
        % Escalar para visualización
        fftResult = mat2gray(magnitude) * scaleFactor;
        fftResult(fftResult > 1) = 1;
        
        % Crear máscara circular para filtrado
        [rows, cols] = size(img);
        [X, Y] = meshgrid(1:cols, 1:rows);
        centerX = cols/2;
        centerY = rows/2;
        mask = sqrt((X - centerX).^2 + (Y - centerY).^2) <= radius;
        
        % Aplicar filtro pasa-bajos
        filteredSpectrum = fftShifted .* mask;
        
        % Reconstruir imagen filtrada
        filteredImg = real(ifft2(ifftshift(filteredSpectrum)));
        filteredImg = mat2gray(filteredImg);
    end
    
    % Función para mostrar resultados
    function showResults(original, processed, fftResult, filteredImg, threshold, minArea, sigma)
        clf(fig); % Limpiar figura antes de redibujar
        
        % Mostrar imagen original
        subplot(2, 3, 1);
        imshow(original, []);
        title('Imagen DICOM Original');
        
        % Mostrar segmentación
        subplot(2, 3, 2);
        imshow(processed);
        title(['Segmentación: Umbral=', num2str(threshold), ', Área=', num2str(minArea), ', σ=', num2str(sigma)]);
        
        % Mostrar espectro de Fourier
        subplot(2, 3, 3);
        imshow(fftResult);
        title('Espectro de Fourier');
        
        % Mostrar imagen filtrada
        subplot(2, 3, 4);
        imshow(filteredImg);
        title('Imagen Filtrada por FFT');
        
        % Mostrar perfil de intensidad original
        subplot(2, 3, 5);
        plot(original(round(size(original,1)/2), :));
        title('Perfil de Intensidad Original');
        xlabel('Posición (píxeles)');
        ylabel('Intensidad');
        grid on;
        
        % Mostrar perfil de intensidad filtrado
        subplot(2, 3, 6);
        plot(filteredImg(round(size(filteredImg,1)/2), :));
        title('Perfil de Intensidad Filtrado');
        xlabel('Posición (píxeles)');
        ylabel('Intensidad');
        grid on;
    end
    
    % Función para guardar resultados
    function saveResults(~, ~)
        [file, path] = uiputfile({'*.png'; '*.jpg'; '*.tif'}, 'Guardar resultados como');
        if isequal(file, 0)
            return;
        end
        
        % Capturar toda la figura
        frame = getframe(fig);
        img = frame2im(frame);
        
        % Guardar imagen
        imwrite(img, fullfile(path, file));
        disp(['Resultados guardados en: ' fullfile(path, file)]);
    end
    
    % Inicializar visualización
    updateDisplay();
end
