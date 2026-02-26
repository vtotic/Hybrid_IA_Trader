# Hybrid EA - AI Engine

This folder contains the Python side of the Hybrid AI Trader Expert Advisor for MetaTrader 5.

## Requisitos Previos

Necesitas tener Python 3.10+ instalado en tu computadora.

## Pasos de Instalación y Uso

### 1. Preparar el Entorno
Abre una terminal (o Símbolo del Sistema) en esta carpeta (`AI_Engine`) y ejecuta:

```bash
# Crear un entorno virtual (recomendado)
python -m venv venv

# Activar el entorno virtual 
# En Windows:
venv\Scripts\activate
# En Mac/Linux:
source venv/bin/activate

# Instalar las dependencias
pip install -r requirements.txt
```

### 2. Entrenar a la IA (Fines de semana o de vez en cuando)
Como estás en **Mac**, MetaTrader 5 (que corre mediante Crossover/Parallels) no puede conectarse directamente con Python por librerías nativas. Por tanto, el entrenamiento lo hacemos exportando el historial:

1. Abre tu MetaTrader 5 (Crossover/Wine/Parallels).
2. Abre el gráfico de **NAS100** (o el instrumento que uses) en **M15** (para Swing).
3. Presiona `Ctrl + S` (o ve a *Archivo -> Guardar como...*) y guarda el archivo con el nombre exacto de **`history_m15.csv`** dentro de esta misma carpeta `AI_Engine`.
4. Repite el proceso para el gráfico en **M5** (para Scalping) y guárdalo como **`history_m5.csv`**.

Una vez tengas esos dos archivos en la carpeta, ejecuta en tu terminal de Mac:

```bash
python train.py
```

Aparecerá una carpeta `models/` con los archivos `swing_model.pkl` y `scalping_model.pkl`.

### 3. Iniciar el Servidor de Predicción (Mientras operas)
Para que el EA en MetaTrader 5 pueda preguntarle a la IA qué hacer en tiempo real, debes iniciar el servidor:

```bash
uvicorn api:app --host 127.0.0.1 --port 5000
```
Verás un mensaje diciendo que el servidor "Uvicorn running on http://127.0.0.1:5000". Déjalo abierto. 

### 4. Lanzar el EA en MetaTrader 5
Ahora ve a MetaTrader 5 y arrastra tu `Hybrid_AI_Trader.mq5` al gráfico. El EA mandará los indicadores del mercado a este servidor local cada vez que encuentre un posible "setup" y usará la Inteligencia Artificial para decidir si toma el trade o lo descarta.
