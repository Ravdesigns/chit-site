/* Shared behaviour for every Deskmates page: scroll reveals + the get-it sheet.
   Per-page config lives on <body data-*>:
     data-mail      where buy / interest emails land
     data-checkout  paste a Gumroad / Lemon Squeezy / Stripe link to skip email
     data-product   product name used in the email subject
     data-price     price string used in the email body                        */
(function(){
  var d = document.body.dataset;
  var MAIL = d.mail || "sisodia.ravindra10@gmail.com";
  var CHECKOUT = d.checkout || "";
  var NAME = d.product || "this widget";
  var PRICE = d.price || "";

  /* scroll reveals */
  var io = new IntersectionObserver(function(es){
    es.forEach(function(e){ if(e.isIntersecting){ e.target.classList.add('in'); io.unobserve(e.target); } });
  }, {threshold:.14});
  document.querySelectorAll('.reveal').forEach(function(el){ io.observe(el); });

  /* get-it sheet */
  var modal = document.getElementById('modal');
  if(!modal) return;
  var mFree = document.getElementById('m-free'), mPro = document.getElementById('m-pro');
  var mail = document.getElementById('mailbtn');
  if(mail){
    var subject = encodeURIComponent(NAME + (PRICE ? " — I'd like to buy" : " — I'd like a copy"));
    var body = encodeURIComponent(
      "Hi Ravindra,\n\nI'd like " + NAME + (PRICE ? " (" + PRICE + ")" : "") +
      ".\n\nName:\nMac (Apple Silicon / Intel):\n\nThanks!");
    mail.href = "mailto:" + MAIL + "?subject=" + subject + "&body=" + body;
  }
  function open(kind){
    if(kind === 'pro' && CHECKOUT){ window.open(CHECKOUT, '_blank'); return; }
    if(mFree) mFree.hidden = kind !== 'free';
    if(mPro)  mPro.hidden  = kind !== 'pro';
    modal.hidden = false; document.body.style.overflow = 'hidden';
  }
  function close(){ modal.hidden = true; document.body.style.overflow = ''; }
  document.querySelectorAll('.buy').forEach(function(b){
    b.addEventListener('click', function(e){ e.preventDefault(); open(b.dataset.buy); });
  });
  var x = document.getElementById('mx');
  if(x) x.addEventListener('click', close);
  modal.addEventListener('click', function(e){ if(e.target === modal) close(); });
  addEventListener('keydown', function(e){ if(e.key === 'Escape') close(); });
})();
