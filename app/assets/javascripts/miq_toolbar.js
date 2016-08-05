ManageIQ.toolbars = {};

ManageIQ.toolbars.findByDataClick = function (toolbar, attr_click) {
  return $(toolbar).find("[data-click='" + attr_click + "']");
};

ManageIQ.toolbars.enableItem = function (toolbar, attr_click) {
  ManageIQ.toolbars.findByDataClick(toolbar, attr_click).removeClass('disabled');
  ManageIQ.angular.rxSubject.onNext({update: attr_click, type: 'enabled', value: true});
};

ManageIQ.toolbars.disableItem = function (toolbar, attr_click) {
  ManageIQ.toolbars.findByDataClick(toolbar, attr_click).addClass('disabled');
  ManageIQ.angular.rxSubject.onNext({update: attr_click, type: 'enabled', value: false});
};

ManageIQ.toolbars.setItemTooltip = function (toolbar, attr_click, tooltip) {
  ManageIQ.toolbars.findByDataClick(toolbar, attr_click).attr('title', tooltip);
  ManageIQ.angular.rxSubject.onNext({update: attr_click, type: 'title', value: tooltip});
};

ManageIQ.toolbars.showItem = function (toolbar, attr_click) {
  ManageIQ.toolbars.findByDataClick(toolbar, attr_click).show();
  ManageIQ.angular.rxSubject.onNext({update: attr_click, type: 'hidden', value: true});
};

ManageIQ.toolbars.hideItem = function (toolbar, attr_click) {
  ManageIQ.toolbars.findByDataClick(toolbar, attr_click).hide();
  ManageIQ.angular.rxSubject.onNext({update: attr_click, type: 'hidden', value: true});
};

ManageIQ.toolbars.markItem = function (toolbar, attr_click) {
  ManageIQ.toolbars.findByDataClick(toolbar, attr_click).addClass('active');
  ManageIQ.angular.rxSubject.onNext({update: attr_click, type: 'selected', value: true});
};

ManageIQ.toolbars.unmarkItem = function (toolbar, attr_click) {
  ManageIQ.toolbars.findByDataClick(toolbar, attr_click).removeClass('active');
  ManageIQ.angular.rxSubject.onNext({update: attr_click, type: 'selected', value: false});
};
