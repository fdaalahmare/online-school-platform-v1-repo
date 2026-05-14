from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', include('apps.core.urls', namespace='core')),
    path('edu/', include('apps.edu.urls', namespace='edu')),
    path('fin/', include('apps.fin.urls', namespace='fin')),
    path('analytics/', include('apps.analytics.urls', namespace='analytics')),
]
