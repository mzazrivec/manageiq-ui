ManageIQ.angular.app.directive('ismultiple', function() {
  return {
    require: 'ngModel',
    link: function(scope, elm, attrs, ctrl) {
      ctrl.$validators.integer = function(modelValue, viewValue) {
        if (ctrl.$isEmpty(modelValue)) {
          return false;
        } else{
          var x = parseInt(viewValue, 10);
          if( x % 4  == 0)
            return true;
        }
        return false;
      };
    }
  };
});
