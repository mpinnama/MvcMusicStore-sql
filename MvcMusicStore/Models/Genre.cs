using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace MvcMusicStore.Models
{
    [Table("genres", Schema = "mvcmusicstore_mvcmusicstore_dbo")]
    public partial class Genre
    {
        [Key]
        [Column("genreid")]
        public int GenreId { get; set; }

        [Column("name")]
        public string Name { get; set; }

        [Column("description")]
        public string Description { get; set; }

        public List<Album> Albums { get; set; }
    }
}