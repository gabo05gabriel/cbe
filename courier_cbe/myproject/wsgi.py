import os
from django.core.wsgi import get_wsgi_application

# Establecer la variable de entorno para el archivo de configuración de Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'myproject.settings')

# Crear la aplicación WSGI
application = get_wsgi_application()
