from django.urls import path

from ...api_views.mobile.views import (
    MobileHomeAPIView,
    MobileWorkScheduleAPIView,
    MobileWorkSiteAPIView,
)

urlpatterns = [
    path("home/", MobileHomeAPIView.as_view(), name="api-mobile-home"),
    path(
        "work-schedule/",
        MobileWorkScheduleAPIView.as_view(),
        name="api-mobile-work-schedule",
    ),
    path("work-site/", MobileWorkSiteAPIView.as_view(), name="api-mobile-work-site"),
]
