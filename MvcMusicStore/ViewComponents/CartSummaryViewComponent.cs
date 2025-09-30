
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using MvcMusicStore.Models;

namespace MvcMusicStore.ViewComponents
{
    public class CartSummaryViewComponent : ViewComponent
    {
        private readonly MusicStoreEntities _storeDB;

        public CartSummaryViewComponent(MusicStoreEntities storeDB)
        {
            _storeDB = storeDB;
        }

        public IViewComponentResult Invoke()
        {
            var cart = ShoppingCart.GetCart(HttpContext);
            ViewData["CartCount"] = cart.GetCount();
            
            return View();
        }
    }
}