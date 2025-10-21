from django.urls import path
from . import views

urlpatterns = [
    path("", views.lista_rutas, name="lista_rutas"),
    path("optimizar/<int:mensajero_id>/", views.optimizar_rutas, name="optimizar_rutas"),
    path("<int:ruta_id>/", views.ver_ruta, name="ver_ruta"),
    # JSON para Flutter
    path("api/mensajeros-json/", views.mensajeros_json, name="mensajeros_json"),
    path("api/rutas-json/<int:mensajero_id>/", views.rutas_json, name="rutas_json"),
]
