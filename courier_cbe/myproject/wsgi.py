import sys
import os

# Asegúrate de que el directorio myproject esté en el path de Python
sys.path.append(os.path.join(os.path.dirname(__file__), 'myproject'))

import django
from django.core.wsgi import get_wsgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'myproject.settings')

application = get_wsgi_application()
