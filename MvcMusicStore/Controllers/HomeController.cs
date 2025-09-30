using System.Collections.Generic;
using System.Linq;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;


namespace MvcMusicStore.Controllers
{
    public class HomeController : Controller
    {
        //
        // GET: /Home/

        MusicStoreEntities storeDB = new MusicStoreEntities();

        public ActionResult Index()
        {
            // Get most popular albums
            var albums = GetTopSellingAlbums(5);

            return View(albums);
        }

private List<Album> GetTopSellingAlbums(int count)
{
    // Temporary implementation until proper data access is resolved
    // This is a placeholder that needs to be replaced with the actual implementation
    return new List<Album>();
}
    }
}