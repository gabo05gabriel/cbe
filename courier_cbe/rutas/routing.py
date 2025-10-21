import os
import math
import numpy as np
import requests
from typing import List, Dict, Tuple, Optional
from sklearn.cluster import KMeans
from joblib import load
from django.conf import settings

# ============================================================
# 🔹 K-MEANS CLUSTERING
# ============================================================
def kmeans_cluster(points: List[Tuple[float, float]], k: Optional[int] = None) -> np.ndarray:
    """
    Agrupa puntos en clusters usando K-Means.
    points: [(lat, lng), ...]
    """
    if not points:
        return np.array([])
    X = np.array(points)
    if not k:
        k = max(1, round(len(points) / 8))  # Regla: ~8 paradas por cluster
    if k >= len(points):
        return np.arange(len(points))  # Cada punto es su propio cluster
    km = KMeans(n_clusters=k, n_init=10, random_state=42)
    return km.fit_predict(X)

# ============================================================
# 🔹 MODELO DE RETRASO (árbol de decisión)
# ============================================================
def load_delay_model(filename: str):
    """
    Carga el modelo .joblib desde rutas/models_ai/
    """
    try:
        path = os.path.join(os.path.dirname(__file__), "models_ai", filename)
        print(f"[DEBUG] Intentando cargar modelo desde: {path}")
        return load(path)
    except Exception as e:
        print(f"[WARNING] No se pudo cargar el modelo {filename}: {e}")
        return None


def score_priority(model, feature_rows: List[Dict]) -> List[float]:
    """
    Usa el árbol de decisión para estimar probabilidad de retraso.
    Convierte lista de dicts en matriz numérica.
    """
    if not feature_rows:
        return []
    if model is None:
        return [0.5] * len(feature_rows)  # Prioridad media si no hay modelo

    try:
        X = []
        for f in feature_rows:
            zona = f.get("zona", 0)
            tipo = f.get("tipo_servicio", "Estandar")
            tipo_val = 0 if str(tipo).lower().startswith("e") else 1  # 0=Estandar, 1=Express
            X.append([zona, tipo_val])
        X = np.array(X)

        proba = model.predict_proba(X)
        return proba[:, 1].tolist() if proba.ndim == 2 else model.predict(X).tolist()

    except Exception as e:
        print(f"[WARNING] Fallo al predecir prioridad: {e}")
        return [0.5] * len(feature_rows)

# ============================================================
# 🔹 MATRIZ DE TIEMPOS (Google Distance Matrix)
# ============================================================
def build_time_matrix_with_google(coords, api_key):
    """
    Construye matriz NxN de tiempos (minutos) entre puntos con Google Distance Matrix.
    coords: [(lat, lng), ...] incluye origen (mensajero) y paradas
    """
    if not coords or len(coords) < 2:
        return np.zeros((len(coords), len(coords)))

    origins = "|".join([f"{lat},{lng}" for lat, lng in coords])
    destinations = origins
    url = "https://maps.googleapis.com/maps/api/distancematrix/json"
    params = {
        "origins": origins,
        "destinations": destinations,
        "key": api_key,
        "mode": "driving"
    }

    try:
        r = requests.get(url, params=params, timeout=10)
        data = r.json()
    except Exception as e:
        print(f"[WARNING] Error al solicitar Distance Matrix: {e}")
        return np.full((len(coords), len(coords)), 1e6)

    n = len(coords)
    M = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            try:
                M[i, j] = data["rows"][i]["elements"][j]["duration"]["value"] / 60.0  # minutos
            except Exception:
                M[i, j] = 1e6  # costo alto si no hay ruta
    return M

# ============================================================
# 🔹 HEURÍSTICA TSP: NEAREST NEIGHBOR + 2-OPT
# ============================================================
def nearest_neighbor_route(cost_matrix: np.ndarray) -> List[int]:
    """
    Construye una ruta inicial con Nearest Neighbor.
    Retorna: orden de índices [0, i1, i2, ..., in]
    """
    n = cost_matrix.shape[0]
    if n == 0:
        return []
    unvisited = set(range(1, n))
    route = [0]
    cur = 0
    while unvisited:
        nxt = min(unvisited, key=lambda j: cost_matrix[cur, j])
        route.append(nxt)
        unvisited.remove(nxt)
        cur = nxt
    return route


def two_opt(route: List[int], dist: np.ndarray, max_iter: int = 200) -> List[int]:
    """
    Mejora la ruta aplicando 2-Opt.
    """
    if not route or len(route) < 4:
        return route
    improved = True
    it = 0
    while improved and it < max_iter:
        improved = False
        it += 1
        for a in range(1, len(route) - 2):
            for b in range(a + 1, len(route) - 1):
                i, j, k, l = route[a - 1], route[a], route[b], route[b + 1]
                if i >= dist.shape[0] or j >= dist.shape[0] or k >= dist.shape[0] or l >= dist.shape[0]:
                    continue
                old = dist[i, j] + dist[k, l]
                new = dist[i, k] + dist[j, l]
                if new + 1e-6 < old:
                    route[a:b + 1] = reversed(route[a:b + 1])
                    improved = True
    return route

# ============================================================
# 🔹 PIPELINE PRINCIPAL: COMPUTE ALGORITHMIC ROUTE
# ============================================================
def compute_algorithmic_route(
    origin: Tuple[float, float],
    stops: List[Dict],
    time_matrix: np.ndarray,
    delay_model=None
):
    """
    Calcula ruta optimizada:
    - Agrupa con K-Means
    - Prioriza con Árbol de Decisión
    - Ordena con NN + 2-Opt
    """
    try:
        if not stops or len(stops) < 1:
            return {
                "order_indices": [],
                "ordered_stops": [],
                "end_time_min": 0
            }

        # ======================================================
        # 1️⃣ Clustering
        pts = [(s["lat"], s["lng"]) for s in stops]
        labels = kmeans_cluster(pts) if len(stops) >= 3 else np.zeros(len(stops), dtype=int)

        # ======================================================
        # 2️⃣ Prioridades (modelo predictivo)
        features = [
            {"zona": int(labels[i]), "tipo_servicio": s.get("tipo_servicio", "Estandar")}
            for i, s in enumerate(stops)
        ]
        priorities = score_priority(delay_model, features)

        # ======================================================
        # 3️⃣ Matriz de costo
        C = np.array(time_matrix, copy=True)
        if C.size == 0:
            return {"order_indices": [], "ordered_stops": [], "end_time_min": 0}

        # ======================================================
        # 4️⃣ Ruta inicial y refinamiento
        route0 = nearest_neighbor_route(C)
        route = two_opt(route0, C)

        # ======================================================
        # 5️⃣ Calcular tiempo total
        total_time = 0.0
        for i in range(len(route) - 1):
            a, b = route[i], route[i + 1]
            if a < C.shape[0] and b < C.shape[0]:
                total_time += C[a, b]

        # ======================================================
        # 6️⃣ Lista de paradas ordenadas (seguro contra índices)
        ordered_stops = []
        for idx in route[1:]:
            if 0 < idx <= len(stops):
                ordered_stops.append(stops[idx - 1])

        return {
            "order_indices": route,
            "ordered_stops": ordered_stops,
            "end_time_min": int(total_time)
        }

    except Exception as e:
        print(f"[ERROR] compute_algorithmic_route(): {e}")
        return {
            "order_indices": [],
            "ordered_stops": [],
            "end_time_min": 0
        }
