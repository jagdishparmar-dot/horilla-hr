from django.urls import path

from .views import *

urlpatterns = [
    path("setup/", GeoFencingSetupGetPostAPIView.as_view()),
    path("setup/<int:pk>/", GeoFencingSetupPutDeleteAPIView.as_view()),
    path("setup-check/", GeoFencingSetUpPermissionCheck.as_view()),
    path("location-check/", GeoFencingEmployeeLocationCheckAPIView.as_view()),
    path("config/", geo_location_config, name="geo-config"),
    path("work-sites/", work_sites, name="work-sites"),
    path("work-sites/<int:pk>/", work_site_update, name="work-site-update"),
    path("work-sites/<int:pk>/delete/", work_site_delete, name="work-site-delete"),
]
