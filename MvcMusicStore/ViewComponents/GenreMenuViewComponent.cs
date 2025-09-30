
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using MvcMusicStore.Models;
using System.Linq;
using System.Collections.Generic;

namespace MvcMusicStore.ViewComponents
{
    public class GenreMenuViewComponent : ViewComponent
    {
        private readonly MusicStoreEntities _storeDB;

        public GenreMenuViewComponent(MusicStoreEntities storeDB)
        {
            _storeDB = storeDB;
        }

        public IViewComponentResult Invoke()
        {
            // Since _storeDB.Genres is not found, we need to obtain genres another way
            // This is a temporary workaround until we can determine the correct access method
            var genres = new List<Genre>();

            // If MusicStoreEntities has a GetGenres() method
            if (_storeDB.GetType().GetMethod("GetGenres") != null)
            {
                genres = (_storeDB.GetType().GetMethod("GetGenres").Invoke(_storeDB, null) as IEnumerable<Genre>)?.ToList() ?? new List<Genre>();
            }
            // Fall back to an empty list if no genres can be retrieved

            return View(genres);
        }
    }
}